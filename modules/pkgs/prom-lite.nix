# prom-lite — ProM Lite 1.4, the process mining framework used in 2AMI10.
#
# Upstream ships a jar bundle plus a launcher script, and separately a Windows
# installer carrying its own JRE 8. That JRE is not incidental: ProM Lite 1.4
# predates the removal of JAXB from the JDK, and importing an XES log reaches
# javax.xml.bind.DatatypeConverter while parsing timestamps, which Java 11 no
# longer has. So this runs on jdk8 rather than the newest JDK that "works".
#
# Two more things the upstream script does not handle here. ProM keeps its
# downloaded package set, its workspace and its UI config next to ProM.ini and
# resolves them relative to the working directory, so the launcher runs it out
# of a writable state directory instead of the store. And Swing paints nothing
# under a non-reparenting window manager unless AWT is told the window manager
# is one, which on niri means a blank window without the env var below.
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
