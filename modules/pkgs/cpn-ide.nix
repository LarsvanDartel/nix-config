# cpn-ide — the Coloured Petri net editor and simulator used in 2AMI10.
# "Windows-only" in name only: the installer (opened with innoextract, no
# Wine) carries a portable Spring Boot backend + Angular frontend + a Linux
# build of the CPN Tools simulator — whose binaries are 32-bit and need the
# pkgsi686 glibc loader patched in below. Two pieces are replaced: the
# frontend is served by the backend (spring.resources.static-locations) to
# stay same-origin and out of CORS, and the Electron-4 shell (file dialogs
# via the long-removed `remote` module) by _process-mining/cpn-ide-app.
{...}: {
  nixpkgs.overlays = [
    (final: _prev: {
      cpn-ide = final.callPackage (
        {
          lib,
          stdenvNoCC,
          fetchurl,
          runtimeShell,
          asar,
          copyDesktopItems,
          makeDesktopItem,
          coreutils,
          util-linux,
          curl,
          electron,
          innoextract,
          jdk11,
          patchelf,
          pkgsi686Linux,
          unzip,
          xdg-utils,
        }:
          stdenvNoCC.mkDerivation (finalAttrs: {
            pname = "cpn-ide";
            version = "1.24.1031";

            src = fetchurl {
              url = "https://cpnide.org/downloads/cpn-ide-${finalAttrs.version}.setup.exe";
              hash = "sha256-GQhOkjJYaBuAnoC1pcGUTaa38HI5fRGUomaJtGqbh5o=";
            };

            nativeBuildInputs = [asar copyDesktopItems innoextract patchelf unzip];

            desktopItems = [
              (makeDesktopItem {
                name = "cpn-ide";
                desktopName = "CPN IDE";
                comment = "Editor and simulator for Coloured Petri nets";
                exec = "cpn-ide";
                icon = "cpn-ide";
                categories = ["Science" "Development"];
                startupWMClass = "cpn-ide";
              })
            ];

            unpackPhase = ''
              runHook preUnpack
              innoextract --silent --extract --output-dir . $src
              runHook postUnpack
            '';

            installPhase = ''
              runHook preInstall

              share=$out/share/cpn-ide
              mkdir -p $share $out/bin

              install -Dm644 app/resources/backend/cpn-ide-back-*.jar $share/cpn-ide-back.jar
              install -Dm644 app/resources/backend/application.properties $share/application.properties

              asar extract app/resources/app.asar app.asar.d
              cp -r app.asar.d/dist/cpn-ide $share/web
              cp -r ${./_process-mining/cpn-ide-app} $share/app

              install -Dm644 $share/web/assets/img/cpn-logo.svg \
                $out/share/icons/hicolor/scalable/apps/cpn-ide.svg

              # The engine unpacks the simulator for the current platform out of
              # its own jar at runtime; the launcher seeds these where it looks,
              # since it only unpacks what is not already there.
              unzip -q -j $share/cpn-ide-back.jar 'BOOT-INF/lib/org.cpntools.accesscpn.engine_*.jar' -d engine
              mkdir -p $share/simulator
              unzip -q -j engine/org.cpntools.accesscpn.engine_*.jar 'simulator/*.x86-linux' -d $share/simulator
              chmod u+w $share/simulator/*
              patchelf \
                --set-interpreter ${pkgsi686Linux.glibc}/lib/ld-linux.so.2 \
                --set-rpath ${pkgsi686Linux.glibc}/lib \
                $share/simulator/cpnmld.x86-linux \
                $share/simulator/run.x86-linux

              substitute ${./_process-mining/cpn-ide.sh} $out/bin/cpn-ide \
                --replace-fail '@shell@' "${runtimeShell}" \
                --replace-fail '@coreutils@' "${coreutils}" \
                --replace-fail '@util_linux@' "${util-linux}" \
                --replace-fail '@java@' "${jdk11}/bin/java" \
                --replace-fail '@curl@' "${curl}/bin/curl" \
                --replace-fail '@electron@' "${lib.getExe electron}" \
                --replace-fail '@xdg_open@' "${xdg-utils}/bin/xdg-open" \
                --replace-fail '@share@' "$share"
              chmod +x $out/bin/cpn-ide

              runHook postInstall
            '';

            meta = {
              description = "Editor and simulator for Coloured Petri nets";
              homepage = "https://cpnide.org/";
              mainProgram = "cpn-ide";
              # The simulator binaries the engine carries are x86 Linux only.
              platforms = ["x86_64-linux" "i686-linux"];
            };
          })
      ) {};
    })
  ];

  perSystem = {pkgs, ...}: {packages.cpn-ide = pkgs.cpn-ide;};
}
