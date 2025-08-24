{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.profiles.common;
in {
  options.profiles.common = {
    enable = mkEnableOption "common configuration";
  };

  config = mkIf cfg.enable {
    browsers.firefox.enable = true;

    system = {
      nix.enable = true;
    };

    cli = {
      terminals.foot.enable = true;
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
        yazi.enable = true;
        zoxide.enable = true;
      };
    };

    security.sops.enable = true;

    styling = {
      enable = true;

      fonts = let
        fontpkgs = config.styling.fonts.pkgs;
      in {
        serif = fontpkgs."DejaVu Serif";
        sansSerif = fontpkgs."DejaVu Sans";
        monospace = fontpkgs."Cozette";
        emoji = fontpkgs."Noto Color Emoji";
        interface = fontpkgs."Cozette";
        extraFonts = [];
      };

      theme.nord = {
        enable = true;
        darkMode = true;
      };

      wallpaper = {
        src = pkgs.fetchurl {
          url = "https://raw.githubusercontent.com/dharmx/walls/6bf4d733ebf2b484a37c17d742eb47e5139e6a14/digital/a_group_of_birds_flying_in_the_sky.jpg";
          hash = "sha256-v6KVInk5JJZPLkOAfC8yuDQtnZtT1DWQI7u6UfG59WY=";
        };
        themed = true;
      };
    };
  };
}
