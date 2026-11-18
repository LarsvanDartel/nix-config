# thunderbird-addons — extensions from addons.thunderbird.net and GitHub,
# repackaged for programs.thunderbird.profiles.<p>.extensions. Pinned to
# exact attachment URLs, never "latest".
{...}: {
  nixpkgs.overlays = [
    (final: _prev: let
      mkThunderbirdXpi = {
        pname,
        version,
        addonId,
        url,
        hash,
      }:
        final.stdenvNoCC.mkDerivation {
          inherit pname version;
          src = final.fetchurl {inherit url hash;};
          dontUnpack = true;
          installPhase = ''
            runHook preInstall
            dir="$out/share/mozilla/extensions/{ec8030f7-c20a-464f-9b0e-13a3a9e97384}"
            mkdir -p "$dir"
            cp "$src" "$dir/${addonId}.xpi"
            runHook postInstall
          '';
          passthru.addonId = addonId;
          meta.platforms = final.lib.platforms.all;
        };
    in {
      thunderbird-addons = {
        # From GitHub, not ATN: ATN's 0.9.1 settings form can never save
        # (loses user activation before permissions.request()). Unsigned as a
        # result — see xpinstall.signatures.required in thunderbird.nix.
        paperless-ngx-uploader = mkThunderbirdXpi {
          pname = "thunderbird-paperless-ngx-uploader";
          version = "1.1.0";
          addonId = "@paperless-uploader.sebastian-xyz";
          url = "https://github.com/sebastian-xyz/paperless-upload-thunderbird/releases/download/v1.1.0/paperless-uploader-v1.1.0.xpi";
          hash = "sha256-WiSXTL9f4N8Cif4AfJRTVxNGHDGB6DoN99TN/Ewv7fE=";
        };

        signature-switch = mkThunderbirdXpi {
          pname = "thunderbird-signature-switch";
          version = "2.20.1";
          addonId = "{2ab1b709-ba03-4361-abf9-c50b964ff75d}";
          url = "https://addons.thunderbird.net/user-media/addons/_attachments/611/signature_switch-2.20.1-tb.xpi";
          hash = "sha256-fjt7MmjYRw3WhXZoxBpQmWOj2fX9/5tnp10ouBoRmoo=";
        };
      };
    })
  ];

  perSystem = {pkgs, ...}: {
    packages = pkgs.thunderbird-addons;
  };
}
