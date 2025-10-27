{
  config,
  lib,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.cosmos.profiles.desktop.addons.fontconfig;
in {
  options.cosmos.profiles.desktop.addons.fontconfig = {
    enable = mkEnableOption "fontconfig";
  };

  config = mkIf cfg.enable {
    fonts.fontconfig = {
      # useEmbeddedBitmaps = true;
      # allowBitmaps = lib.mkForce true;
      # antialias = true;
      # hinting = {
      #   enable = false;
      #   style = "none";
      # };
      # subpixel = {
      #   lcdfilter = "none";
      #   rgba = "none";
      # };

      # FIXME: Fixes https://github.com/NixOS/nixpkgs/issues/449657
      localConf = ''
        <?xml version="1.0"?>
        <!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
        <fontconfig>
          <description>Accept bitmap fonts</description>
        <!-- Accept bitmap fonts -->
         <selectfont>
          <acceptfont>
           <pattern>
             <patelt name="outline"><bool>false</bool></patelt>
           </pattern>
          </acceptfont>
         </selectfont>
        </fontconfig>
      '';
    };
  };
}
