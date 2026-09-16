# home.wrapper-stylix — stylix base for the wrapped-package catalog
# (modules/meta/hm-wrappers.nix): mirrors the desktop's Nord scheme + fonts
# without the cosmos.desktops.* options. autoEnable off — each wrapped program
# enables its own target.
{inputs, ...}: {
  den.aspects.home.wrapper-stylix.homeManager = {pkgs, ...}: {
    imports = [inputs.stylix.homeModules.stylix];

    stylix = {
      enable = true;
      autoEnable = false;
      polarity = "dark";
      base16Scheme = "${pkgs.base16-schemes}/share/themes/nord.yaml";

      image = pkgs.runCommand "placeholder.png" {nativeBuildInputs = [pkgs.imagemagick];} ''
        magick -size 1x1 xc:black $out
      '';

      fonts = {
        monospace = {
          package = pkgs.cozette;
          name = "Cozette";
        };
        sansSerif = {
          package = pkgs.dejavu_fonts;
          name = "DejaVu Sans";
        };
        serif = {
          package = pkgs.dejavu_fonts;
          name = "DejaVu Serif";
        };
        emoji = {
          package = pkgs.noto-fonts-color-emoji;
          name = "Noto Color Emoji";
        };
        sizes.terminal = 9;
      };
    };
  };
}
