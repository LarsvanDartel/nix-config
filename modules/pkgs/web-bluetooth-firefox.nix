# web-bluetooth-firefox-host — native messaging host giving Firefox forks a
# `navigator.bluetooth`: an extension implements the API in the page and
# forwards over stdio to a Python host driving BlueZ through bleak. Packaged
# rather than upstream's install.sh (curls a script, venv + pip under
# ~/.local/share), which would put an unmanaged Python env outside the store.
# NOTE: upstream is candid that the code was written with generative AI —
# worth knowing for anything standing between a web page and the Bluetooth
# stack.
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

            # BlueZ refuses a connect while a discovery scan runs
            # (org.bluez.Error.InProgress), and the host lets the two
            # overlap; pages are entitled to that (Chrome allows it), so the
            # patch pauses discovery around the connect. Restarting is the
            # load-bearing half: the extension tracks scanning with one
            # boolean, sending watch_advertisements only on its false->true
            # edge, so a scanner quietly left stopped is never re-asked for —
            # every later picker comes up empty.
            patches = [./_web-bluetooth/pause-scan-on-connect.patch];

            # `name` must match the manifest file's basename (what the
            # extension asks for over stdio); allowed_extensions gates who
            # may talk to it.
            installPhase = ''
              runHook preInstall

              install -Dm644 webbluetooth_host.py \
                $out/share/web-bluetooth-firefox/webbluetooth_host.py

              mkdir -p $out/bin
              # The host logs to stderr, which the browser discards — so when
              # something fails between the page and the Bluetooth stack there
              # is nothing to read. Redirect it to a file under the state
              # directory, truncated per launch so it stays the size of one
              # session rather than growing without bound.
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

      # The extension, rebuilt from source with one fix: upstream nests the
      # advertisement event's fields under CustomEvent's `detail`, but the
      # spec puts manufacturerData/rssi/uuids on the event itself —
      # cstimer.net reads event.manufacturerData for a GAN cube's MAC, gets
      # undefined, and fails. Shipped unsigned: Zen defaults
      # xpinstall.signatures.required to false; stock Firefox would need the
      # AMO build, bug and all.
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

            # Laid out like home-manager's firefox addon packages (xpi named
            # for the extension id, passthru.addonId alongside) so
            # extensions.packages can install it — that mechanism replaces
            # what is already in the profile, unlike ExtensionSettings. The
            # manifest id must survive the rebuild: the host's
            # allowed_extensions names it.
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
