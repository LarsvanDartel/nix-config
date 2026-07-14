{config, ...}: let
  inherit (config.flake.modules.homeManager) keyring;
in {
  # Proton Pass (desktop app).
  flake.modules.homeManager.proton-pass = {pkgs, ...}: {
    home.packages = [pkgs.proton-pass];

    cosmos.system.impermanence.persist.directories = [".config/Proton Pass"];
  };

  # Proton Pass CLI (`pass-cli`).
  flake.modules.homeManager.proton-pass-cli = {pkgs, ...}: {
    imports = [keyring];

    home.packages = [pkgs.proton-pass-cli];

    # pass-cli's login session is expected to live in the keyring; the config
    # path is undocumented, so ".config/proton-pass" is a best guess.
    cosmos.system.impermanence.persist.directories = [".config/proton-pass"];
  };
}
