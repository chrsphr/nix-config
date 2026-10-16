# Newer opencode than nixpkgs-unstable ships. Bump `version` + `src` hash on
# each upstream release; `node_modulesHash` only when bun deps change.
# why: docs/notes.md#opencode-version
final: prev:
let
  version = "1.19.3";
  src = prev.fetchFromGitHub {
    owner = "anomalyco";
    repo = "opencode";
    tag = "v${version}";
    hash = "sha256-NI994pBur/Lt3wSDamFxE4sb0fKq2+Kue/77i/8BTlo=";
  };
  node_modulesHash = "sha256-RLHrfyBM6fMglKyEkdkW+Mmfzzr6q/U7R38goaQcIhA=";
in
{
  opencode = prev.opencode.overrideAttrs (finalAttrs: prevAttrs: {
    inherit version src;
    passthru = prevAttrs.passthru // {
      node_modules = prevAttrs.passthru.node_modules.overrideAttrs (_: {
        inherit version src;
        outputHash = node_modulesHash;
      });
    };
  });
}
