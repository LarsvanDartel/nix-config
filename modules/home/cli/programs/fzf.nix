{...}: {
  flake.modules.homeManager.fzf = {
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
}
