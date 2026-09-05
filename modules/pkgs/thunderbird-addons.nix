# thunderbird-addons — extensions and themes from addons.thunderbird.net,
# repackaged for home-manager's programs.thunderbird.profiles.<p>.extensions.
#
# That option expects each package to drop its xpi under
# share/mozilla/extensions/{ec8030f7-c20a-464f-9b0e-13a3a9e97384}/<addon-id>.xpi
# — the same layout modules/pkgs/web-bluetooth-firefox.nix uses for a Zen
# extension. Unlike Zen's add-ons, none of these are on NUR's
# rycee.firefox-addons: that overlay only tracks addons.mozilla.org, and
# Thunderbird's add-ons live on a separate site with its own catalog.
#
# Each is otherwise an unmodified download fetched by the exact attachment
# URL (not a "latest" alias, which is a moving target) so the hash stays
# meaningful. All but paperless-ngx-uploader come signed from ATN as-is;
# that one is pinned to a GitHub release instead — see its own comment.
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
        # Uploads the open message's PDF attachments to a paperless-ngx
        # instance from a context menu — the on-demand alternative to giving
        # paperless-ngx its own IMAP account against Proton Bridge.
        #
        # From GitHub, not ATN: ATN's listing is stuck on 0.9.1, whose
        # options.js awaits browser.permissions.contains() before calling
        # permissions.request() — the await loses the click's transient user
        # activation, so request() throws and the settings form can never
        # actually save a URL. Fixed upstream in 1.1.0 (also fixes
        # permissions.request() rejecting a match pattern that includes a
        # port, which a self-hosted paperless URL usually does), but ATN
        # review hasn't caught up. Unsigned as a result — see
        # xpinstall.signatures.required in thunderbird.nix.
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

        theme-ancient-time = mkThunderbirdXpi {
          pname = "thunderbird-theme-ancient-time";
          version = "1.0";
          addonId = "{46950db7-5edd-486f-bcd1-277af4133845}";
          url = "https://addons.thunderbird.net/user-media/addons/_attachments/987189/the_universe_of_ancient_times-1.0-tb.xpi";
          hash = "sha256-pw98/Hpmf7uU3nAKM6DN9lRbArbPa5U85VOlHZyBGIE=";
        };

        theme-nord-dark = mkThunderbirdXpi {
          pname = "thunderbird-theme-nord-dark";
          version = "1.0";
          addonId = "nord-dark@yannic-hock.themes.thunderbird.net";
          url = "https://addons.thunderbird.net/user-media/addons/_attachments/988111/nord_dark-1.0-tb.xpi";
          hash = "sha256-z782Ywv0D8Lipj2mLzXtgXyRD3aEONDNcyLSP4dXH4M=";
        };
      };
    })
  ];

  perSystem = {pkgs, ...}: {
    packages = pkgs.thunderbird-addons;
  };
}
