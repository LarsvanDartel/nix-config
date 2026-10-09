# git-remote-tino — git remote helper bridging git to a TINO bucket's REST
# API (TINO speaks no git protocol), for machines with no mesh path to the
# host. Usage/design doc is the script's header (_tino/git-remote-tino.py).
# gitMinimal goes on PATH: push shells out to git in the caller's repo.
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
            # python3 here lets patchShebangs rewrite the shebang to a store
            # path; otherwise it depends on an ambient python3.
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
