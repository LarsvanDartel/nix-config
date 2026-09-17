# home.tino — git-remote-tino (pkgs/git-remote-tino.nix): clone, fetch
# and push TINO buckets as git repositories over TINO's public REST API
# (tino.lvdar.nl), no NetBird path needed — TINO speaks no git wire
# protocol, so this helper is the only git-native transport. The
# helper's own header comment is the full usage and design doc; the
# short form is `git clone tino::<bucket>`.
#
# keys/tino/api-key (nix-secrets: users/common/secrets.yaml) is the
# personal TINO API key, deployed the same way home.ssh deploys private
# keys: sops-nix decrypts it fresh on every activation straight to
# ~/.config/tino/api-key, so unlike a manually-dropped file it survives
# voyager's impermanence wipe without needing its own persist entry —
# activation *is* what repopulates it. Minted/rotated on TINO's side
# (/var/lib/tino/api_keys.yml on endeavour); committer access per
# bucket is granted there, not here — see the helper's own header for
# why editor is not enough.
{...}: {
  den.aspects.home.tino.homeManager = {
    config,
    pkgs,
    ...
  }: {
    home.packages = [pkgs.git-remote-tino];

    sops.secrets."keys/tino/api-key" = {
      sopsFile = "${config.cosmos.security.sops.sopsFolder}/common/secrets.yaml";
      path = "${config.home.homeDirectory}/.config/tino/api-key";
    };
  };
}
