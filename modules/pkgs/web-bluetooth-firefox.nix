# web-bluetooth-firefox-host — the native messaging host that gives Firefox
# forks a `navigator.bluetooth`.
#
# Firefox has never shipped Web Bluetooth and shows no sign of doing so, which
# leaves anything speaking to a BLE device over the web — a smart cube on
# cstimer.net, say — working in Chrome and nowhere else. This bridges the gap:
# an extension implements the API in the page and forwards each call over
# stdio to a Python host that drives BlueZ through bleak.
#
# Packaged rather than installed by the project's own install.sh, which curls a
# script, builds a venv under ~/.local/share and pip-installs bleak into it.
# That works and is entirely reasonable for other distributions; here it would
# put an unmanaged Python environment outside the store and write a manifest
# home-manager would not know about.
#
# The upstream README says plainly that the project has been written with
# generative AI. It is a small amount of code standing between a web page and
# the Bluetooth stack, so that is worth knowing before granting a site access
# to a device.
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
          # bleak >= 1 removed BleakClient.get_services(); the host reads
          # client.services instead, which is the post-1.x shape, so nixpkgs'
          # current bleak is the right one rather than the >=0.20 the project's
          # installer pins.
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

            # The manifest's `name` is what the extension asks for over stdio
            # and has to match the file's own basename; `allowed_extensions` is
            # what stops any other extension talking to it.
            installPhase = ''
              runHook preInstall

              install -Dm644 webbluetooth_host.py \
                $out/share/web-bluetooth-firefox/webbluetooth_host.py

              mkdir -p $out/bin
              cat > $out/bin/webbluetooth-host <<EOF
              #!${runtimeShell}
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

      # The extension, rebuilt from source with one fix.
      #
      # Upstream dispatches the advertisement event with everything nested
      # under CustomEvent's `detail`:
      #
      #   d.dispatchEvent(new CustomEvent('advertisementreceived', { detail }));
      #
      # The Web Bluetooth spec puts manufacturerData, rssi, uuids and the rest
      # directly on the event. cstimer.net reads event.manufacturerData to
      # recover a GAN cube's MAC — the cube's protocol needs it — gets
      # undefined, and fails with "can't access property has, ua is undefined".
      # The data is all present and correctly shaped, one level too deep.
      #
      # Shipped unsigned, which works because Zen is built with
      # MOZ_REQUIRE_SIGNING false and defaults xpinstall.signatures.required to
      # false. On a stock Firefox this would need signing and the AMO build
      # would have to be used instead, bug and all.
      web-bluetooth-firefox-extension = final.callPackage (
        {
          lib,
          stdenvNoCC,
          zip,
        }:
          stdenvNoCC.mkDerivation {
            pname = "web-bluetooth-firefox-extension";
            version = "1.1";

            inherit (final.web-bluetooth-firefox-host) src;

            nativeBuildInputs = [zip];

            postPatch = ''
              substituteInPlace webbluetooth-firefox-extension/polyfill.js \
                --replace-fail \
                  "d.dispatchEvent(new CustomEvent('advertisementreceived', { detail }));" \
                  "const _ev = new CustomEvent('advertisementreceived', { detail }); Object.assign(_ev, detail, { device: d }); d.dispatchEvent(_ev);"
            '';

            # The id inside manifest.json is what the native host's
            # allowed_extensions names and what the install policy keys on, so
            # it has to survive the rebuild unchanged.
            installPhase = ''
              runHook preInstall
              mkdir -p $out/share/mozilla-extensions
              cd webbluetooth-firefox-extension
              zip -qr $out/share/mozilla-extensions/webbluetooth@rfvx.github.io.xpi .
              runHook postInstall
            '';

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
