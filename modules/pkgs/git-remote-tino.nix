# git-remote-tino — packages the TINO git remote helper (docs/src/notes/git-remote-tino.md#usage); push shells out to git, hence gitMinimal.
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
