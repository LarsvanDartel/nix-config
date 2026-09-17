# home.tino — git-remote-tino (pkgs/git-remote-tino.nix): clone, fetch
# and push TINO buckets as git repositories over TINO's public REST API
# (tino.lvdar.nl), no NetBird path needed — TINO speaks no git wire
# protocol, so this helper is the only git-native transport. The
# helper's own header comment is the full usage and design doc; the
# short form is `git clone tino::<bucket>`.
#
# ~/.config/tino/api-key holds the personal TINO API key and is
# persisted: it is a plain file rather than a sops secret because it is
# a per-user credential minted and rotated on TINO's side
# (/var/lib/tino/api_keys.yml on endeavour) — no host should be able to
# read it, only the user who pushed it there. voyager's impermanence
# wipes unpersisted ~/.config on every boot, which is exactly why the
# directory is listed here rather than left to chance.
{...}: {
  den.aspects.home.tino.homeManager = {pkgs, ...}: {
    home.packages = [pkgs.git-remote-tino];

    cosmos.system.impermanence.persist.directories = [".config/tino"];
  };
}
