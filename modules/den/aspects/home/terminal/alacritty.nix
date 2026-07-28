# home.alacritty
{...}: {
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
