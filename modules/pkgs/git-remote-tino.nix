# git-remote-tino — a git remote helper (gitremote-helpers(7)) that bridges
# git to a TINO bucket's REST API, so buckets can be cloned/fetched/pushed
# from machines with no SSH/NetBird path to the TINO host: TINO speaks no
# git wire protocol at all, its public surface is the web UI and the REST
# API behind https://tino.lvdar.nl (published ungated through gaia's
# netbird-proxy — see hosts/gaia.nix). The helper's own header comment is
# the full usage and design doc:
#
#   git clone tino::abc-meetings
#   git fetch / git push                     # fast-forward only
#   auth: TINO_API_KEY, ~/.config/tino/api-key, or tino://<key>@host/<bucket>
#
# Script lives in _tino/ beside the packaging assets of pkgs/tino.nix —
# same upstream, same assets dir. gitMinimal is wrapped onto PATH because
# push shells out to git (diff-tree, rev-list, cat-file) in the caller's
# repository via GIT_DIR.
{...}: {
  nixpkgs.overlays = [
    (final: _prev: {
      git-remote-tino = final.callPackage (
        {
          lib,
          stdenvNoCC,
          python3,
          gitMinimal,
          makeWrapper,
        }:
          stdenvNoCC.mkDerivation {
            pname = "git-remote-tino";
            version = "1.0.0";

            dontUnpack = true;
            # python3 in nativeBuildInputs is what lets patchShebangs
            # rewrite `#!/usr/bin/env python3` to a store path — without
            # it the shebang survives and the helper only runs where the
            # caller's ambient PATH happens to have a python3 (seen as
            # `env: python3: No such file or directory` when it doesn't).
            nativeBuildInputs = [makeWrapper python3];

            installPhase = ''
              runHook preInstall
              install -Dm755 ${./_tino/git-remote-tino.py} $out/bin/git-remote-tino
              patchShebangs $out/bin/git-remote-tino
              wrapProgram $out/bin/git-remote-tino \
                --prefix PATH : ${lib.makeBinPath [gitMinimal]}
              runHook postInstall
            '';

            meta = {
              description = "Git remote helper for TINO buckets over their REST API";
              mainProgram = "git-remote-tino";
              platforms = lib.platforms.unix;
            };
          }
      ) {};
    })
  ];

  perSystem = {pkgs, ...}: {packages.git-remote-tino = pkgs.git-remote-tino;};
}
