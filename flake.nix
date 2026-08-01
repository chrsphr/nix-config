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
    hostsConfig = import ./hosts.nix { inherit lib; };

    # Single shared unstable instance. Each `import nixpkgs { … }` evaluates a
    # whole nixpkgs; instantiating it once here instead of per-specialArgs site
    # is the biggest eval-time/memory win in this flake.
    pkgs-unstable = import nixpkgs-unstable { inherit system; config.allowUnfree = true; };

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

    # Generate deploy-rs nodes for all hosts that exist in both hosts.nix and nixosConfigurations
    mkDeployNodes = configs:
      lib.mapAttrs (name: cfg:
        let
          targetSystem = configs.${name}.pkgs.stdenv.hostPlatform.system;
        in {
          hostname = hostsConfig.hosts.${name}.ip;
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
      ) (lib.filterAttrs (name: _: hostsConfig.hosts ? ${name}) configs);
  in {
    nixosConfigurations = {
      pihole-1 = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./lxc/pihole-1.nix
        ];
      };
      pihole-2 = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./lxc/pihole-2.nix
        ];
      };
      immich = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { inherit pkgs-unstable; };
        modules = [
          ./lxc/immich.nix
          sops-nix.nixosModules.sops
        ];
      };
      caddy = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./lxc/caddy.nix
          sops-nix.nixosModules.sops
        ];
      };
      plex = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { inherit pkgs-unstable; };
        modules = [
          ./lxc/plex.nix
        ];
      };
      tailscale = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./lxc/tailscale.nix
        ];
      };
      transmission = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./lxc/transmission.nix
        ];
      };
      sonarr = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./lxc/sonarr.nix
        ];
      };
      uptime = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./lxc/uptime.nix
          sops-nix.nixosModules.sops
        ];
      };

      beeper = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./lxc/beeper.nix
        ];
      };


      gb-grid = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = {
          gb-grid-pkg = gb-grid.packages.x86_64-linux.default;
        };
        modules = [
          ./lxc/gb-grid.nix
          gb-grid.nixosModules.default
          sops-nix.nixosModules.sops
        ];
      };


      chris-framework = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { inherit pkgs-unstable; deploy-rs-pkg = deploy-rs.packages.${system}.default; };
        modules = [
          ./chris-framework.nix
          ./hardware/framework-disko.nix
          disko.nixosModules.disko
          nixos-hardware.nixosModules.framework-amd-ai-300-series
        ] ++ mkHomeModules ./home/framework.nix;
      };

      chris-desktop = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { inherit pkgs-unstable; deploy-rs-pkg = deploy-rs.packages.${system}.default; };
        modules = [
          ./chris-desktop.nix
          ./hardware/desktop-disko.nix
          disko.nixosModules.disko
        ] ++ mkHomeModules ./home/desktop.nix;
      };

      chris-wsl = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { inherit pkgs-unstable; deploy-rs-pkg = deploy-rs.packages.${system}.default; };
        modules = [
          nixos-wsl.nixosModules.default
          ./chris-wsl.nix
        ] ++ mkHomeModules ./home/wsl.nix;
      };
    };

    deploy.nodes = mkDeployNodes self.nixosConfigurations;

    # Only check the platform we actually build/deploy from — evaluating
    # deployChecks for every deploy-rs platform quadruples `nix flake check`.
    checks.${system} = deploy-rs.lib.${system}.deployChecks self.deploy;
  };
}