#!/usr/bin/env bash
set -euo pipefail

FLAKE="/home/chris/nix-config"

# Extract remote servers from hosts.nix, filtered to only those with a nixosConfiguration.
echo "Reading hosts from hosts.nix..."
servers=$(nix eval --impure --raw --expr '
  let
    lib = import <nixpkgs/lib>;
    hosts = (import '"${FLAKE}"'/hosts.nix { inherit lib; }).hosts;
    flakeConfigs = builtins.attrNames (builtins.getFlake (toString '"${FLAKE}"')).nixosConfigurations;
    remoteServers = lib.filterAttrs (name: _: builtins.elem name flakeConfigs) hosts;
  in lib.concatStringsSep "\n" (lib.mapAttrsToList (name: cfg: "${name} ${cfg.ip}") remoteServers)
')

BOLD='\033[1m'
NC='\033[0m'

echo ""
echo -e "${BOLD}The following servers will be deployed:${NC}"
echo ""
while IFS=' ' read -r name ip; do
  printf "  %-20s %s\n" "$name" "$ip"
done <<< "$servers"
echo ""

read -rp "Proceed with deployment? [y/N] " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
  echo "Aborted."
  exit 0
fi
echo ""

# deploy-rs builds locally, copies closures to remotes, activates with magic rollback.
# Pass extra flags through, e.g.: ./deploy-all.sh --dry-activate
exec nix run github:serokell/deploy-rs -- "$FLAKE" "$@"
