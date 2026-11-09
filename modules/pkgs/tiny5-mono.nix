# tiny5-mono — Tiny5 Mono, a 5-pixel monospace font (github:Gissio/font_Tiny5Mono).
# Upstream has no tags or releases: pinned by commit. Only the static TTFs are
# installed; the variable TTFs share their family names and would shadow them.
{...}: {
  nixpkgs.overlays = [
    (final: _prev: {
      tiny5-mono = final.stdenvNoCC.mkDerivation {
        pname = "tiny5-mono";
        version = "3.001-unstable-2026-11-07";

        src = final.fetchFromGitHub {
          owner = "Gissio";
          repo = "font_Tiny5Mono";
          rev = "36478e1f5abba5f4215ec7d9e6e59888d4c97cb5";
          hash = "sha256-jXNwK3Ayp5dpfs2ucfqjvT3Akr7GUmlIhd7+ikiwILI=";
        };

        # The Makefile rebuilds the fonts in a pip venv; the committed TTFs are the release.
        dontBuild = true;

        installPhase = ''
          runHook preInstall
          install -Dm644 -t $out/share/fonts/truetype fonts/ttf/*.ttf
          runHook postInstall
        '';

        meta = {
          description = "5-pixel monospace font with LCD, CRT and Matrix styles";
          homepage = "https://github.com/Gissio/font_Tiny5Mono";
          license = final.lib.licenses.ofl;
          platforms = final.lib.platforms.all;
        };
      };
    })
  ];
}
