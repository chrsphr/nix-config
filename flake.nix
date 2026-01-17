{
  description = "chris's nixos configurations";
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
  };
  outputs = { self, nixpkgs, nixos-hardware }: {
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
        modules = [
          ./immich.nix
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
        modules = [
          ./plex.nix
        ];
        
      };            
      chris-framework = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./chris-framework.nix
          nixos-hardware.nixosModules.framework-amd-ai-300-series
        ];
      };

      chris-desktop = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./chris-desktop.nix
        ];
      };
    };
  };
}