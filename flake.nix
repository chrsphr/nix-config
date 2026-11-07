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
    #
    # The opencode overlay repackages an x86_64 npm binary, so only apply it on
    # x86_64. All current hosts are x86_64, including cloudhutch.
    mkPkgsUnstable = targetSystem: import nixpkgs-unstable {
      system = targetSystem;
      config.allowUnfree = true;
      # libolm, pulled by the beeper bridges (end-to-bridge encryption).
      config.permittedInsecurePackages = [ "olm-3.2.16" ];
      # opencode ahead of nixpkgs. why: docs/notes.md#opencode-version
      overlays = lib.optionals (targetSystem == system) [ (import ./overlays/opencode.nix) ];
    };
    pkgs-unstable = mkPkgsUnstable system;

    # Base builder: every host gets a matching pkgs-unstable in specialArgs.
    # hostSystem can override the architecture; all current hosts are x86_64.
    mkHost = {
      modules,
      specialArgs ? {},
      nixpkgsInput ? nixpkgs,
      overlays ? [],
      hostSystem ? system,
      unstable ? (if hostSystem == system then pkgs-unstable else mkPkgsUnstable hostSystem),
    }:
      nixpkgsInput.lib.nixosSystem {
        system = hostSystem;
        modules = modules ++ lib.optionals (overlays != []) [ { nixpkgs.overlays = overlays; } ];
        specialArgs = { pkgs-unstable = unstable; } // specialArgs;
      };

    # Home-manager integration shared by the personal machines. Only the home
    # profile path differs per host, so the rest is factored out here.
    #
    # The non-x86 branches are retained for future hosts; the current fleet is
    # entirely x86_64.
    mkHomeModules = homeProfile: {
      hostSystem ? system,
      unstable ? (if hostSystem == system then pkgs-unstable else mkPkgsUnstable hostSystem),
      mcpPkg ? (if hostSystem == system then mcp-nixos.packages.${system}.default else null),
    }: [
      home-manager.nixosModules.home-manager
      {
        home-manager.useGlobalPkgs = true;
        home-manager.useUserPackages = true;
        home-manager.extraSpecialArgs = {
          pkgs-unstable = unstable;
        } // lib.optionalAttrs (mcpPkg != null) {
          mcp-nixos-pkg = mcpPkg;
        };
        home-manager.backupFileExtension = "hm-bak";
        home-manager.users.chris = import homeProfile;
      }
    ];

    # Personal machine: home-manager plus the pinned deploy-rs CLI.
    mkMachine = {
      host,
      home,
      extraModules ? [],
      nixpkgsInput ? nixpkgs,
      overlays ? [],
      hostSystem ? system,
      unstable ? (if hostSystem == system then pkgs-unstable else mkPkgsUnstable hostSystem),
      mcpPkg ? (if hostSystem == system then mcp-nixos.packages.${system}.default else null),
    }: mkHost {
      modules = [ host ] ++ extraModules ++ mkHomeModules home { inherit hostSystem unstable mcpPkg; };
      specialArgs.deploy-rs-pkg = deploy-rs.packages.${hostSystem}.default;
      inherit nixpkgsInput overlays hostSystem unstable;
    };

    # Generate deploy-rs nodes for all hosts that exist in both lib/network.nix and nixosConfigurations
    mkDeployNodes = configs:
      lib.mapAttrs (name: cfg:
        let
          targetSystem = configs.${name}.pkgs.stdenv.hostPlatform.system;
        in {
          hostname = network.getIP name;
          profiles.system = {
            user = "root";
            sshUser = "deploy";
            path = deploy-rs.lib.${targetSystem}.activate.nixos configs.${name};
            # Build on the laptop and copy to the target. cloudhutch is
            # IPv6-only and cannot fetch GitHub, so remote builds are never an
            # option for it even though it is now x86_64.
            remoteBuild = network.hosts.${name}.remoteBuild or (targetSystem != system);
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

      # cloudhutch: IPv6-only x86_64 netcup VPS, minimal tailnet node. No
      # containers; deploy-rs reaches it over the tailnet (see lib/network.nix
      # `address`). Install: docs/cloudhutch-install.md
      cloudhutch = mkMachine {
        host = ./hosts/cloudhutch.nix;
        home = ./home/server.nix;
        extraModules = [
          ./hardware/cloudhutch-disko.nix
          disko.nixosModules.disko
        ];
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

      ### Installer ISOs (build only, not deployed)
      # Minimal SSH-enabled live ISO for key-only remote installs.
      # Build: nix build .#nixosConfigurations.install-iso.config.system.build.isoImage
      install-iso = mkHost {
        modules = [ ./hosts/install-iso.nix ];
      };
      # cloudhutch's x86_64 ISO: static IPv6 + baked-in disko config.
      # Build: nix build .#nixosConfigurations.cloudhutch-iso.config.system.build.isoImage
      cloudhutch-iso = mkHost {
        modules = [ ./hosts/cloudhutch-iso.nix ];
      };
    };

    deploy.nodes = mkDeployNodes self.nixosConfigurations;

    # Only the deploy platform. why: docs/notes.md#single-platform-deploychecks
    checks.${system} = deploy-rs.lib.${system}.deployChecks self.deploy;
  };
}
