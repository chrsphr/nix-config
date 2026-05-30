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
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
  outputs = { self, nixpkgs, nixpkgs-unstable, nixos-hardware, nixos-wsl, home-manager, sops-nix, deploy-rs, gb-grid, disko }:
  let
    system = "x86_64-linux";
    lib = nixpkgs.lib;
    hostsConfig = import ./hosts.nix { inherit lib; };

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
          };
        }
      ) (lib.filterAttrs (name: _: hostsConfig.hosts ? ${name}) configs);
  in {
    nixosConfigurations = {
      pihole-1 = nixpkgs-unstable.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./lxc/pihole-1.nix
        ];
      };
      pihole-2 = nixpkgs-unstable.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./lxc/pihole-2.nix
        ];
      };
      immich = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { pkgs-unstable = import nixpkgs-unstable { system = "x86_64-linux"; config = { allowUnfree = true; }; }; };
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
      transcode = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./lxc/transcode.nix
        ];
      };   
      plex = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { pkgs-unstable = import nixpkgs-unstable { system = "x86_64-linux"; config = { allowUnfree = true; }; }; };
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
      grafana = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./lxc/grafana.nix
        ];
      };
      photosdotmcneill = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./lxc/photosdotmcneill.nix
          sops-nix.nixosModules.sops
        ];
      };
      uptime = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./lxc/uptime.nix
          sops-nix.nixosModules.sops
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
        specialArgs = { pkgs-unstable = import nixpkgs-unstable { system = "x86_64-linux"; config = { allowUnfree = true; }; }; deploy-rs-pkg = deploy-rs.packages.${system}.default; };
        modules = [
          ./chris-framework.nix
          ./hardware/framework-disko.nix
          disko.nixosModules.disko
          nixos-hardware.nixosModules.framework-amd-ai-300-series
          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.extraSpecialArgs = { pkgs-unstable = import nixpkgs-unstable { system = "x86_64-linux"; config = { allowUnfree = true; }; }; };
            home-manager.users.chris = import ./home/framework.nix;
          }
        ];
      };

      chris-desktop = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { pkgs-unstable = import nixpkgs-unstable { system = "x86_64-linux"; config = { allowUnfree = true; }; }; deploy-rs-pkg = deploy-rs.packages.${system}.default; };
        modules = [
          ./chris-desktop.nix
          ./hardware/desktop-disko.nix
          disko.nixosModules.disko
          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.extraSpecialArgs = { pkgs-unstable = import nixpkgs-unstable { system = "x86_64-linux"; config = { allowUnfree = true; }; }; };
            home-manager.users.chris = import ./home/desktop.nix;
          }
        ];
      };

      chris-wsl = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { pkgs-unstable = import nixpkgs-unstable { system = "x86_64-linux"; config = { allowUnfree = true; }; }; deploy-rs-pkg = deploy-rs.packages.${system}.default; };
        modules = [
          nixos-wsl.nixosModules.default
          ./chris-wsl.nix
          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.extraSpecialArgs = { pkgs-unstable = import nixpkgs-unstable { system = "x86_64-linux"; config = { allowUnfree = true; }; }; };
            home-manager.users.chris = import ./home/wsl.nix;
          }
        ];
      };
    };

    deploy.nodes = mkDeployNodes self.nixosConfigurations;

    checks = builtins.mapAttrs (system: deployLib: deployLib.deployChecks self.deploy) deploy-rs.lib;
  };
}