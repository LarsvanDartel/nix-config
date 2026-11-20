# tiny5-mono — Tiny5 Mono pixel font, square-pixel Regular and Italic cut from the variable fonts (pixel-exact at multiples of 8px).
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

        nativeBuildInputs = [(final.python3.withPackages (p: [p.fonttools]))];

        # Replaces the Makefile, which rebuilds every style in a pip venv.
        buildPhase = ''
          runHook preBuild
          for style in Regular Italic; do
            src="fonts/variable/Tiny5Mono[BLED,JITT,ROND,wdth,wght].ttf"
            [ "$style" = Italic ] && src="fonts/variable/Tiny5Mono-Italic[BLED,JITT,ROND,wdth,wght].ttf"
            fonttools varLib.instancer "$src" wdth=143.82 wght=400 ROND=0 BLED=0 JITT=0 \
              -o "Tiny5Mono-$style.ttf"
          done
          runHook postBuild
        '';

        installPhase = ''
          runHook preInstall
          install -Dm644 -t $out/share/fonts/truetype Tiny5Mono-*.ttf
          runHook postInstall
        '';

        meta = {
          description = "5-pixel monospace font, square-pixel cut";
          homepage = "https://github.com/Gissio/font_Tiny5Mono";
          license = final.lib.licenses.ofl;
          platforms = final.lib.platforms.all;
        };
      };
    })
  ];
}
