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

    # Single shared unstable instance. Each `import nixpkgs { … }` evaluates a
    # whole nixpkgs; instantiating it once here instead of per-specialArgs site
    # is the biggest eval-time/memory win in this flake.
    pkgs-unstable = import nixpkgs-unstable { inherit system; config.allowUnfree = true; };

    # Base builder: every host gets pkgs-unstable in specialArgs — harmless
    # where unused (only immich, plex and chris-desktop consume it).
    mkHost = { modules, specialArgs ? {} }: lib.nixosSystem {
      inherit system modules;
      specialArgs = { inherit pkgs-unstable; } // specialArgs;
    };

    # Proxmox LXC container; the sops variant adds sops-nix for hosts with
    # secrets/<hostname>.yaml.
    mkLxc = path: mkHost { modules = [ path ]; };
    mkSopsLxc = path: mkHost { modules = [ path sops-nix.nixosModules.sops ]; };

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
            # Magic rollback's confirmation SSH hangs intermittently on this
            # fleet (immich/caddy/sonarr all hit it 2026-07-03; activation
            # itself succeeded every time, then the confirm round-trip stalled
            # and triggered a spurious rollback — one interrupted run even left
            # beeper half-activated with sshd down). Disable it fleet-wide and
            # verify deploys by checking services instead; Proxmox console is
            # the recovery path if an activation ever goes bad.
            magicRollback = false;
          };
        }
      ) (lib.filterAttrs (name: _: network.hosts ? ${name}) configs);
  in {
    nixosConfigurations = {
      ### Proxmox LXC containers (hosts/lxc/)
      pihole-1 = mkLxc ./hosts/lxc/pihole-1.nix;
      pihole-2 = mkLxc ./hosts/lxc/pihole-2.nix;
      plex = mkLxc ./hosts/lxc/plex.nix;
      tailscale = mkLxc ./hosts/lxc/tailscale.nix;
      transmission = mkLxc ./hosts/lxc/transmission.nix;
      sonarr = mkLxc ./hosts/lxc/sonarr.nix;
      beeper = mkLxc ./hosts/lxc/beeper.nix;
      immich = mkSopsLxc ./hosts/lxc/immich.nix;
      caddy = mkSopsLxc ./hosts/lxc/caddy.nix;
      uptime = mkSopsLxc ./hosts/lxc/uptime.nix;
      gb-grid = mkHost {
        modules = [
          ./hosts/lxc/gb-grid.nix
          gb-grid.nixosModules.default
          sops-nix.nixosModules.sops
        ];
        specialArgs.gb-grid-pkg = gb-grid.packages.${system}.default;
      };

      ### Test VM (containers prototype)
      # hutch-test: VM that runs services as NixOS containers (see hosts/containers/).
      hutch-test = mkHost {
        modules = [
          ./hosts/hutch-test.nix
          ./hardware/hutch-test.nix
          ./hardware/hutch-test-disko.nix
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

      ### Installer ISO (build only, not deployed)
      # Minimal SSH-enabled live ISO for key-only remote installs.
      # Build: nix build .#nixosConfigurations.install-iso.config.system.build.isoImage
      install-iso = mkHost {
        modules = [ ./hosts/install-iso.nix ];
      };
    };

    deploy.nodes = mkDeployNodes self.nixosConfigurations;

    # Only check the platform we actually build/deploy from — evaluating
    # deployChecks for every deploy-rs platform quadruples `nix flake check`.
    checks.${system} = deploy-rs.lib.${system}.deployChecks self.deploy;
  };
}
