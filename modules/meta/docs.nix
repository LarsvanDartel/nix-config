# docs — the mdBook in docs/: `nix build .#docs`; live preview `mdbook serve docs` in the devshell.
{cosmosLib, ...}: {
  perSystem = {
    config,
    pkgs,
    ...
  }: {
    packages.docs = pkgs.runCommand "cosmos-docs" {nativeBuildInputs = [pkgs.mdbook];} ''
      mdbook build ${cosmosLib.get-flake-path "docs"} --dest-dir $out
    '';
    # Fails on a SUMMARY entry without a file (create-missing = false).
    checks.docs = config.packages.docs;
  };
}
