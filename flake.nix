{
  description = "Homelab NixOS Containers";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";
  };

  outputs = { self, nixpkgs }: {
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

    };
  };
}