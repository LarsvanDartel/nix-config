# Standalone stylix home-manager module used as the theming base for every
# wrapped package (see modules/meta/hm-wrappers.nix). Mirrors the desktop's
# Nord scheme + font stack (styling/_impl/themes/nord.nix + _impl/fonts/*) so a
# `nix run .#foo` program looks like it does on the desktop, without depending
# on the `cosmos.desktops.common.styling.*` option layer (which doesn't exist
# inside an isolated wrap evaluation).
{inputs, ...}: {
  flake.modules.homeManager.wrapper-stylix = {pkgs, ...}: {
    imports = [inputs.stylix.homeModules.stylix];

    stylix = {
      enable = true;
      # Do NOT auto-enable every target: that themes GTK/KDE/GNOME/blender/etc and
      # bloats each wrapper's closure + bind list. Each wrapped program enables its
      # own stylix target explicitly (see modules/meta/hm-wrappers.nix).
      autoEnable = false;
      polarity = "dark";
      base16Scheme = "${pkgs.base16-schemes}/share/themes/nord.yaml";

      # stylix wants an image for its wallpaper target; a 1x1 placeholder keeps
      # the eval happy without pulling the real wallpaper into every wrapper.
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
