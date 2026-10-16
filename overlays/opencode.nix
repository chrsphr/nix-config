# opencode 2.x is published to npm (@opencode/cli), not as a GitHub release that
# nixpkgs builds from. Repackage the prebuilt linux-x64 binary.
# why: docs/notes.md#opencode-version
final: prev:
{
  opencode = prev.stdenv.mkDerivation (finalAttrs: {
    pname = "opencode";
    version = "2.0.31";

    src = prev.fetchurl {
      url = "https://registry.npmjs.org/@opencode/cli-linux-x64/-/cli-linux-x64-${finalAttrs.version}.tgz";
      hash = "sha512-RYbqR/HzKTH9OSh98VOt78bgQ8sgidUCCCKR9CABSc06AFxZdycezIg8dUmh+uBdp2mf4ckWVq9BbGblbxtFZQ==";
    };

    sourceRoot = "package";

    nativeBuildInputs = [ prev.patchelf ];

    dontConfigure = true;
    dontBuild = true;
    # autoPatchelfHook's rpath rewrite breaks the appended bun payload (version
    # reports 1.4.2), so only the interpreter is set. Stripping would also corrupt it.
    dontStrip = true;
    dontPatchELF = true;

    installPhase = ''
      runHook preInstall
      install -Dm755 bin/opencode $out/bin/opencode
      patchelf --set-interpreter ${prev.stdenv.cc.bintools.dynamicLinker} $out/bin/opencode
      runHook postInstall
    '';

    meta = {
      description = "AI coding agent built for the terminal";
      homepage = "https://opencode.ai";
      license = prev.lib.licenses.mit;
      platforms = [ "x86_64-linux" ];
      mainProgram = "opencode";
    };
  });
}
