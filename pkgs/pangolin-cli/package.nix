{
  lib,
  stdenv,
  buildGoModule,
  fetchFromGitHub,
  installShellFiles,
  versionCheckHook,
  nix-update-script,
}:
buildGoModule (finalAttrs: {
  pname = "pangolin-cli";
  version = "0.3.2";

  src = fetchFromGitHub {
    owner = "fosrl";
    repo = "cli";
    tag = finalAttrs.version;
    hash = "sha256-pB4sPiOhTTX4y4J7T6B6sLZHGMdrCAbgWtUKCJmtV88=";
  };

  vendorHash = "sha256-hZj/PDNsWGplSrOgzJtL09/oFXHZ4zdS7BiRS+oy5bw=";

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

  doInstallCheck = true;
  nativeInstallCheckInputs = [versionCheckHook];
  versionCheckKeepEnvironment = ["HOME"];
  versionCheckProgramArg = "version";

  passthru.updateScript = nix-update-script {};

  meta = {
    description = "Pangolin CLI tool and VPN client";
    homepage = "https://github.com/fosrl/cli";
    changelog = "https://github.com/fosrl/cli/releases/tag/${finalAttrs.version}";
    license = lib.licenses.agpl3Only;
    mainProgram = "pangolin";
  };
})
