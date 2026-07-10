{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf mkMerge;

  cfg = config.cosmos.proton.pass;
in {
  options.cosmos.proton.pass = {
    gui.enable = mkEnableOption "Proton Pass (desktop app)";

    cli.enable = mkEnableOption "Proton Pass CLI (`pass-cli`)";
  };

  config = mkMerge [
    (mkIf cfg.gui.enable {
      home.packages = [pkgs.proton-pass];

      cosmos.system.impermanence.persist.directories = [".config/Proton Pass"];
    })

    (mkIf cfg.cli.enable {
      home.packages = [pkgs.proton-pass-cli];

      # pass-cli's login session is expected to live in the keyring; the config
      # path is undocumented, so ".config/proton-pass" is a best guess. If the
      # login doesn't survive a reboot, check where `pass-cli login` wrote and
      # add that directory here.
      cosmos.security.keyring.enable = true;

      cosmos.system.impermanence.persist.directories = [".config/proton-pass"];
    })
  ];
}
