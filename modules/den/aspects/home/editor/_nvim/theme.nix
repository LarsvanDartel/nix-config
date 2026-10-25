# nvim theme — what stylix's nixvim target set (mini.base16, guifont, neovide
# opacity), from cosmosStyling since no stylix target reaches the package.
{
  cosmosStyling,
  pkgs,
  ...
}: let
  colors = (cosmosStyling.colors pkgs).withHashtag;
  monospace = cosmosStyling.font pkgs cosmosStyling.fonts.monospace;
in {
  plugins.mini = {
    enable = true;
    modules.base16.palette = {
      inherit
        (colors)
        base00
        base01
        base02
        base03
        base04
        base05
        base06
        base07
        base08
        base09
        base0A
        base0B
        base0C
        base0D
        base0E
        base0F
        ;
    };
  };

  # stylix uses fonts.sizes.terminal, which defaults to the font's recommendedSize.
  opts.guifont = "${monospace.name}:h${toString monospace.recommendedSize}";

  extraConfigLua = ''
    if vim.g.neovide then
      vim.g.neovide_normal_opacity = ${toString cosmosStyling.opacity.terminal}
    end
  '';
}
