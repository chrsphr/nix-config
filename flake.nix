{
  description = "chris's nixos configurations";
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
    nixos-wsl = {
      url = "github:nix-community/NixOS-WSL/main";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
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
  };
  outputs = { self, nixpkgs, nixpkgs-unstable, nixos-hardware, nixos-wsl, home-manager, sops-nix, deploy-rs }:
  let
    system = "x86_64-linux";
    lib = nixpkgs.lib;
    hostsConfig = import ./hosts.nix { inherit lib; };

    # Generate deploy-rs nodes for all hosts that exist in both hosts.nix and nixosConfigurations
    mkDeployNodes = configs:
      lib.mapAttrs (name: cfg: {
        hostname = hostsConfig.hosts.${name}.ip;
        profiles.system = {
          user = "root";
          sshUser = "deploy";
          path = deploy-rs.lib.${system}.activate.nixos configs.${name};
          remoteBuild = false;
        };
      }) (lib.filterAttrs (name: _: hostsConfig.hosts ? ${name}) configs);
  in {
    nixosConfigurations = {
      pihole-1 = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./pihole-1.nix
        ];
      };
      pihole-2 = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./pihole-2.nix
        ];
      };
      immich = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { pkgs-unstable = import nixpkgs-unstable { system = "x86_64-linux"; config = { allowUnfree = true; }; }; };
        modules = [
          ./immich.nix
          sops-nix.nixosModules.sops
        ];
      };
      caddy = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./caddy.nix
          sops-nix.nixosModules.sops
        ];
      };
      transcode = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./transcode.nix
        ];
      };   
      plex = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { pkgs-unstable = import nixpkgs-unstable { system = "x86_64-linux"; config = { allowUnfree = true; }; }; };
        modules = [
          ./plex.nix
        ];
      };
      tailscale = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./tailscale.nix
        ];
      };
      transmission = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./transmission.nix
        ];
      };
      sonarr = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./sonarr.nix
        ];
      };
      grafana = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./grafana.nix
        ];
      };
      photosdotmcneill = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./photosdotmcneill.nix
          sops-nix.nixosModules.sops
        ];
      };
      uptime-kuma = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { pkgs-unstable = import nixpkgs-unstable { system = "x86_64-linux"; }; };
        modules = [
          ./uptime-kuma.nix
          sops-nix.nixosModules.sops
        ];
      };
      paperless = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { pkgs-unstable = import nixpkgs-unstable { system = "x86_64-linux"; }; };
        modules = [
          ./paperless.nix
          sops-nix.nixosModules.sops
        ];
      };
      claude-agent = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = {
          pkgs-unstable = import nixpkgs-unstable {
            system = "x86_64-linux";
            config = { allowUnfree = true; };
          };
        };
        modules = [
          ./claude-agent.nix
          sops-nix.nixosModules.sops
        ];
      };

      chris-framework = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { pkgs-unstable = import nixpkgs-unstable { system = "x86_64-linux"; config = { allowUnfree = true; }; }; deploy-rs-pkg = deploy-rs.packages.${system}.default; };
        modules = [
          ./chris-framework.nix
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