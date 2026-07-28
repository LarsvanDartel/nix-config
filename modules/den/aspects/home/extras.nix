# home.{fzf,ranger,alacritty} — standalone programs (not in the baseline; used by
# the wrapped-package catalog and available for hosts that want them).
{...}: {
  den.aspects.home.fzf.homeManager = {
    config,
    lib,
    ...
  }: let
    inherit (lib.modules) mkForce;
  in {
    programs.fzf = {
      enable = true;
      enableZshIntegration = config.programs.zsh.enable;
      colors = with config.lib.stylix.colors.withHashtag;
        mkForce {
          "bg" = base00;
          "bg+" = base02;
          "fg" = base05;
          "fg+" = base05;
          "header" = base0E;
          "hl" = base08;
          "hl+" = base08;
          "info" = base0A;
          "marker" = base06;
          "pointer" = base06;
          "prompt" = base0E;
          "spinner" = base06;
        };
    };
  };

  den.aspects.home.ranger.homeManager = {...}: {
    programs.ranger.enable = true;
  };

  den.aspects.home.alacritty.homeManager = {pkgs, ...}: {
    programs.alacritty = {
      enable = true;
      settings.terminal.shell = {
        program = "${pkgs.zsh}/bin/zsh";
        args = ["-l"];
      };
    };
  };
}
