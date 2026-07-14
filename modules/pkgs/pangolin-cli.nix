{...}: {
  nixpkgs.overlays = [
    (final: _prev: {
      pangolin-cli = final.callPackage (
        {
          lib,
          stdenv,
          buildGoModule,
          fetchFromGitHub,
          installShellFiles,
          nix-update-script,
        }:
          buildGoModule (finalAttrs: {
            pname = "pangolin-cli";
            version = "0.9.0";

            src = fetchFromGitHub {
              owner = "fosrl";
              repo = "cli";
              tag = finalAttrs.version;
              hash = "sha256-TWn0xwjQTIZ5oNrMScGko27HpVfwMi/LpLFCQADmhKw=";
            };

            vendorHash = "sha256-6rWNo84a+aqcHgjtNqrgfYnERSO6AdWwZ36+mhxk6Z8=";

            nativeBuildInputs = [installShellFiles];

            postInstall =
              ''
                mv $out/bin/cli $out/bin/pangolin
              ''
              + lib.optionalString (stdenv.buildPlatform.canExecute stdenv.hostPlatform) ''
                installShellCompletion --cmd pangolin \
                  --bash <($out/bin/pangolin completion bash) \
                  --fish <($out/bin/pangolin completion fish) \
                  --zsh <($out/bin/pangolin completion zsh)
              '';

            passthru.updateScript = nix-update-script {};

            meta = {
              description = "Pangolin CLI tool and VPN client";
              homepage = "https://github.com/fosrl/cli";
              changelog = "https://github.com/fosrl/cli/releases/tag/${finalAttrs.version}";
              license = lib.licenses.agpl3Only;
              mainProgram = "pangolin";
            };
          })
      ) {};
    })
  ];

  perSystem = {pkgs, ...}: {packages.pangolin-cli = pkgs.pangolin-cli;};
}
