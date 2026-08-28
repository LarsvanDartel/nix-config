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
    })
  ];

  perSystem = {pkgs, ...}: {packages.web-bluetooth-firefox-host = pkgs.web-bluetooth-firefox-host;};
}
