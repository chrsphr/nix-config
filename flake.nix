{
  description = "chris's nixos configurations";
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
    nixos-wsl = {
      url = "github:nix-community/NixOS-WSL/main";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    deploy-rs = {
      url = "github:serokell/deploy-rs";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    gb-grid = {
      url = "github:chrsphr/gb-grid";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # MCP server giving Claude Code live NixOS / Home Manager package + option search.
    mcp-nixos = {
      url = "github:utensils/mcp-nixos";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
  outputs = { self, nixpkgs, nixpkgs-unstable, nixos-hardware, nixos-wsl, home-manager, sops-nix, deploy-rs, gb-grid, disko, mcp-nixos }:
  let
    system = "x86_64-linux";
    lib = nixpkgs.lib;
    network = import ./lib/network.nix { inherit lib; };

    # Single shared unstable instance — the biggest eval-time win here.
    # why: docs/notes.md#shared-pkgs-unstable
    pkgs-unstable = import nixpkgs-unstable { inherit system; config.allowUnfree = true; };

    # Base builder: every host gets pkgs-unstable in specialArgs.
    mkHost = { modules, specialArgs ? {} }: lib.nixosSystem {
      inherit system modules;
      specialArgs = { inherit pkgs-unstable; } // specialArgs;
    };

    # Home-manager integration shared by the personal machines. Only the home
    # profile path differs per host, so the rest is factored out here.
    mkHomeModules = homeProfile: [
      home-manager.nixosModules.home-manager
      {
        home-manager.useGlobalPkgs = true;
        home-manager.useUserPackages = true;
        home-manager.extraSpecialArgs = {
          inherit pkgs-unstable;
          mcp-nixos-pkg = mcp-nixos.packages.${system}.default;
        };
        home-manager.backupFileExtension = "hm-bak";
        home-manager.users.chris = import homeProfile;
      }
    ];

    # Personal machine: home-manager plus the pinned deploy-rs CLI.
    mkMachine = { host, home, extraModules ? [] }: mkHost {
      modules = [ host ] ++ extraModules ++ mkHomeModules home;
      specialArgs.deploy-rs-pkg = deploy-rs.packages.${system}.default;
    };

    # Generate deploy-rs nodes for all hosts that exist in both lib/network.nix and nixosConfigurations
    mkDeployNodes = configs:
      lib.mapAttrs (name: cfg:
        let
          targetSystem = configs.${name}.pkgs.stdenv.hostPlatform.system;
        in {
          hostname = network.hosts.${name}.ip;
          profiles.system = {
            user = "root";
            sshUser = "deploy";
            path = deploy-rs.lib.${targetSystem}.activate.nixos configs.${name};
            remoteBuild = targetSystem != system;
            # Spurious rollbacks from hung confirm SSH — do not re-enable.
            # history: docs/notes.md#magicrollback-disabled
            magicRollback = false;
          };
        }
      ) (lib.filterAttrs (name: _: network.hosts ? ${name}) configs);
  in {
    nixosConfigurations = {
      ### Baremetal servers (containers; hutch additionally = NAS)
      # Containers are deployed BY deploying their parent — see README
      # "Server + services". sops-nix and gb-grid pass through for the
      # container configs that need them.
      hutch = mkHost {
        modules = [
          ./hosts/hutch.nix
          ./hardware/hutch.nix
          ./hardware/hutch-disko.nix
          disko.nixosModules.disko
        ];
        specialArgs = {
          inherit sops-nix gb-grid;
          gb-grid-pkg = gb-grid.packages.${system}.default;
        };
      };
      # minihutch (.3): compute only — no ZFS, no NFS, no backup.
      minihutch = mkHost {
        modules = [
          ./hosts/minihutch.nix
          ./hardware/minihutch.nix
          ./hardware/minihutch-disko.nix
          disko.nixosModules.disko
        ];
        specialArgs = {
          inherit sops-nix gb-grid;
          gb-grid-pkg = gb-grid.packages.${system}.default;
        };
      };

      ### Personal machines (hosts/)
      chris-framework = mkMachine {
        host = ./hosts/chris-framework.nix;
        home = ./home/framework.nix;
        extraModules = [
          ./hardware/framework-disko.nix
          disko.nixosModules.disko
          nixos-hardware.nixosModules.framework-amd-ai-300-series
        ];
      };
      chris-desktop = mkMachine {
        host = ./hosts/chris-desktop.nix;
        home = ./home/desktop.nix;
        extraModules = [
          ./hardware/desktop-disko.nix
          disko.nixosModules.disko
        ];
      };
      chris-wsl = mkMachine {
        host = ./hosts/chris-wsl.nix;
        home = ./home/wsl.nix;
        extraModules = [ nixos-wsl.nixosModules.default ];
      };

      ### Installer ISO (build only, not deployed)
      # Minimal SSH-enabled live ISO for key-only remote installs.
      # Build: nix build .#nixosConfigurations.install-iso.config.system.build.isoImage
      install-iso = mkHost {
        modules = [ ./hosts/install-iso.nix ];
      };
    };

    deploy.nodes = mkDeployNodes self.nixosConfigurations;

    # Only the deploy platform. why: docs/notes.md#single-platform-deploychecks
    checks.${system} = deploy-rs.lib.${system}.deployChecks self.deploy;
  };
}
