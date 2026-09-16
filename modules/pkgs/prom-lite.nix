# prom-lite — ProM Lite 1.4, the process mining framework used in 2AMI10.
# jdk8, not a newer JDK that merely "works": importing an XES log reaches
# javax.xml.bind.DatatypeConverter, removed from the JDK after 8. The
# launcher runs it out of a writable state directory (ProM resolves its
# package set/workspace/config relative to the cwd), and exports
# _JAVA_AWT_WM_NONREPARENTING — Swing paints nothing under niri without it.
{...}: {
  nixpkgs.overlays = [
    (final: _prev: {
      prom-lite = final.callPackage (
        {
          lib,
          stdenvNoCC,
          fetchurl,
          runtimeShell,
          copyDesktopItems,
          makeDesktopItem,
          coreutils,
          util-linux,
          jdk8,
        }:
          stdenvNoCC.mkDerivation (finalAttrs: {
            pname = "prom-lite";
            version = "1.4";

            src = fetchurl {
              url = "https://www.promtools.org/prom6/downloads/47004/prom-lite-${finalAttrs.version}-all-platforms.tar.gz";
              hash = "sha256-pWW86bQPk6c5nBW9W7PmbjBJH2H4JIJBpPtoC+qvNRQ=";
            };

            sourceRoot = ".";

            nativeBuildInputs = [copyDesktopItems];

            desktopItems = [
              (makeDesktopItem {
                name = "prom-lite";
                desktopName = "ProM Lite";
                comment = "Framework for process mining";
                exec = "prom-lite";
                icon = "prom-lite";
                categories = ["Science" "Development"];
                startupWMClass = "org-processmining-contexts-uitopia-UI";
              })
            ];

            installPhase = ''
              runHook preInstall

              mkdir -p $out/share/prom-lite $out/bin
              cp -r dist lib ProM.ini $out/share/prom-lite/

              # The only icon in the bundle is a banner; the duck lives in a
              # package ProM downloads at runtime.
              install -Dm644 lib/images/logo_branding.png $out/share/pixmaps/prom-lite.png

              substitute ${./_process-mining/prom-lite.sh} $out/bin/prom-lite \
                --replace-fail '@shell@' "${runtimeShell}" \
                --replace-fail '@coreutils@' "${coreutils}" \
                --replace-fail '@util_linux@' "${util-linux}" \
                --replace-fail '@java@' "${jdk8}/bin/java" \
                --replace-fail '@share@' "$out/share/prom-lite"
              chmod +x $out/bin/prom-lite

              runHook postInstall
            '';

            meta = {
              description = "Framework for process mining";
              homepage = "https://promtools.org/";
              license = lib.licenses.gpl3Plus;
              mainProgram = "prom-lite";
              platforms = lib.platforms.unix;
            };
          })
      ) {};
    })
  ];

  perSystem = {pkgs, ...}: {packages.prom-lite = pkgs.prom-lite;};
}
