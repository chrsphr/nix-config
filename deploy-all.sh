#!/usr/bin/env bash
set -euo pipefail

FLAKE="/home/chris/nix-config"

# Extract remote servers from hosts.nix, filtered to only those with a nixosConfiguration.
echo "Reading hosts from hosts.nix..."
servers=$(nix eval --impure --raw --expr '
  let
    f = builtins.getFlake (toString '"${FLAKE}"');
    lib = f.inputs.nixpkgs.lib;
    hosts = (import '"${FLAKE}"'/hosts.nix { inherit lib; }).hosts;
    flakeConfigs = builtins.attrNames f.nixosConfigurations;
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
# Use the installed deploy binary (from the flake's pinned deploy-rs input, via
# common-desktop.nix) — `nix run github:serokell/deploy-rs` fetched and
# evaluated an unpinned copy on every run.
if ! command -v deploy >/dev/null; then
  echo "deploy not found — rebuild this machine first (it ships deploy-rs-pkg)." >&2
  exit 1
fi
exec deploy "$FLAKE" "$@"
