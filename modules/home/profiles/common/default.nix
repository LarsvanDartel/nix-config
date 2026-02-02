{
  config,
  lib,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.cosmos.profiles.common;
in {
  options.cosmos.profiles.common = {
    enable = mkEnableOption "common configuration";
  };

  config = mkIf cfg.enable {
    cosmos = {
      system = {
        nix.enable = true;
      };

      cli = {
        shells.zsh.enable = true;
        programs = {
          prompt.oh-my-posh.enable = true;
          nvim.enable = true;
          ssh.enable = true;
          bat.enable = true;
          btop.enable = true;
          direnv.enable = true;
          eza.enable = true;
          fd.enable = true;
          git = {
            enable = true;
            user = "LarsvanDartel";
            email = "larsvandartel73@gmail.com";
          };
          lazygit.enable = true;
          ripgrep.enable = true;
          xh.enable = true;
          yazi = {
            enable = true;
            defaultApplication = true;
          };
          zoxide.enable = true;
        };
      };

      security.sops.enable = true;
    };
  };
}
