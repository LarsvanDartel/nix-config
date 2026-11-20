# web-bluetooth-firefox — native messaging host and extension giving Firefox forks `navigator.bluetooth`; upstream code is AI-written, review changes.
{...}: {
  nixpkgs.overlays = [
    (final: _prev: {
      web-bluetooth-firefox-host = final.callPackage (
        {
          lib,
          stdenvNoCC,
          fetchFromGitHub,
          python3,
          runtimeShell,
        }: let
          # Host reads client.services (bleak >= 1 shape), so nixpkgs'
          # current bleak is right, not the >=0.20 the installer pins.
          python = python3.withPackages (ps: [ps.bleak]);
        in
          stdenvNoCC.mkDerivation (finalAttrs: {
            pname = "web-bluetooth-firefox-host";
            version = "0-unstable-2026-08-28";

            src = fetchFromGitHub {
              owner = "rfvx";
              repo = "web-bluetooth-firefox-linux";
              rev = "1aaf5ea62e8d11769c0cd643dcf59972f54fc9ca";
              hash = "sha256-t0hzIAB2/ZFprUFSsqiwtM+VlOUXLsbNy3crq+b+lLc=";
            };

            dontBuild = true;

            # BlueZ refuses a connect during discovery; the patch pauses and restarts it, since the extension
            # only re-sends watch_advertisements on a false->true edge.
            patches = [./_web-bluetooth/pause-scan-on-connect.patch];

            # `name` must match the manifest file's basename.
            installPhase = ''
              runHook preInstall

              install -Dm644 webbluetooth_host.py \
                $out/share/web-bluetooth-firefox/webbluetooth_host.py

              mkdir -p $out/bin
              # The browser discards the host's stderr; log to a per-launch file under the state directory.
              cat > $out/bin/webbluetooth-host <<EOF
              #!${runtimeShell}
              log="\''${XDG_STATE_HOME:-\$HOME/.local/state}/webbluetooth-firefox"
              mkdir -p "\$log"
              exec 2>"\$log/host.log"
              exec ${python}/bin/python3 $out/share/web-bluetooth-firefox/webbluetooth_host.py "\$@"
              EOF
              chmod +x $out/bin/webbluetooth-host

              mkdir -p $out/lib/mozilla/native-messaging-hosts
              cat > $out/lib/mozilla/native-messaging-hosts/webbluetooth_host.json <<EOF
              {
                "name": "webbluetooth_host",
                "description": "WebBluetooth Native Messaging Host",
                "path": "$out/bin/webbluetooth-host",
                "type": "stdio",
                "allowed_extensions": ["webbluetooth@rfvx.github.io"]
              }
              EOF

              runHook postInstall
            '';

            meta = {
              description = "Native messaging host implementing Web Bluetooth for Firefox on Linux";
              homepage = "https://github.com/rfvx/web-bluetooth-firefox-linux";
              license = lib.licenses.mit;
              platforms = lib.platforms.linux;
              mainProgram = "webbluetooth-host";
            };
          })
      ) {};

      # Rebuilt to put advertisement fields on the event, as the spec expects, not under `detail`.
      # Unsigned: Zen defaults xpinstall.signatures.required to false.
      web-bluetooth-firefox-extension = final.callPackage (
        {
          lib,
          stdenvNoCC,
          zip,
        }:
          stdenvNoCC.mkDerivation {
            pname = "web-bluetooth-firefox-extension";
            # Upstream is 1.1; bumped because Firefox will not replace an
            # installed extension with the same id at the same version.
            version = "1.1.1";

            inherit (final.web-bluetooth-firefox-host) src;

            nativeBuildInputs = [zip];

            # A patch, not substituteInPlace: the change spans several lines
            # whose exact text matters.
            patches = [./_web-bluetooth/advertisement-event-shape.patch];

            # Laid out like home-manager's firefox addons for extensions.packages; the manifest id must
            # match the host's allowed_extensions.
            installPhase = ''
              runHook preInstall
              dir="$out/share/mozilla/extensions/{ec8030f7-c20a-464f-9b0e-13a3a9e97384}"
              mkdir -p "$dir"
              cd webbluetooth-firefox-extension
              zip -qr "$dir/webbluetooth@rfvx.github.io.xpi" .
              runHook postInstall
            '';

            passthru.addonId = "webbluetooth@rfvx.github.io";

            meta = {
              description = "Web Bluetooth polyfill extension for Firefox, with the advertisement-event fix";
              homepage = "https://github.com/rfvx/web-bluetooth-firefox-linux";
              license = lib.licenses.mit;
              platforms = lib.platforms.linux;
            };
          }
      ) {};
    })
  ];

  perSystem = {pkgs, ...}: {
    packages = {
      inherit (pkgs) web-bluetooth-firefox-host web-bluetooth-firefox-extension;
    };
  };
}
