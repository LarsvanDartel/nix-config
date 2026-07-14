# Alacritty as a plain home-manager module. Not imported into any host by
# default (foot is the desktop terminal); it exists so it can be wrapped into a
# portable, stylix-themed package via modules/meta/hm-wrappers.nix.
{...}: {
  flake.modules.homeManager.alacritty = {pkgs, ...}: {
    programs.alacritty = {
      enable = true;
      settings.terminal.shell = {
        program = "${pkgs.zsh}/bin/zsh";
        args = ["-l"];
      };
    };
  };
}
