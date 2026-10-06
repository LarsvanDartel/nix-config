{...}: {
  nixpkgs.overlays = [
    (final: _prev: {
      mcrl2 = final.callPackage (
        {
          lib,
          stdenv,
          fetchFromGitHub,
          cmake,
          libGLU,
          libGL,
          qt6,
          boost,
        }:
          stdenv.mkDerivation rec {
            version = "202607.0";
            pname = "mcrl2";

            src = fetchFromGitHub {
              owner = "mCRL2org";
              repo = "mCRL2";
              tag = "mcrl2-${version}";
              hash = "sha256-zVcfMlEmTjyuPwf86voI8d0jBzqqVph5Cx120bzI3Hw=";
            };

            nativeBuildInputs = [cmake];
            buildInputs = [
              libGLU
              libGL
              qt6.qtbase
              boost
            ];

            dontWrapQtApps = true;

            meta = {
              broken = stdenv.hostPlatform.isDarwin;
              description = "Toolset for model-checking concurrent systems and protocols";
              longDescription = ''
                A formal specification language with an associated toolset,
                that can be used for modelling, validation and verification of
                concurrent systems and protocols
              '';
              homepage = "https://www.mcrl2.org/";
              license = lib.licenses.boost;
              platforms = lib.platforms.unix;
            };
          }
      ) {};
    })
  ];

  perSystem = {pkgs, ...}: {packages.mcrl2 = pkgs.mcrl2;};
}
