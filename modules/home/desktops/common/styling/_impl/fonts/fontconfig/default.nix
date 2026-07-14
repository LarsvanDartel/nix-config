{
  lib,
  config,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;
  inherit (lib.strings) concatStrings;

  cfg = config.cosmos.desktops.common.styling.fonts.fontconfig;

  aliasConfig = font: ''
    <alias>
      <family>${font.name}</family>

      <prefer>
        <family>${font.name}</family>
    ${concatStrings (map (font: "    <family>${font}</family>\n") font.fallbackFonts)}
      </prefer>
    </alias>
  '';

  configContent = concatStrings (
    map (
      font: aliasConfig config.cosmos.desktops.common.styling.fonts.pkgs.${font}
    )
    config.cosmos.desktops.common.styling.fonts.installed
  );
in {
  options.cosmos.desktops.common.styling.fonts.fontconfig = {
    enable = mkEnableOption "fontconfig";
  };

  config = mkIf cfg.enable {
    fonts.fontconfig = {
      enable = true;

      defaultFonts = with config.cosmos.desktops.common.styling.fonts; {
        serif = [serif.name];
        sansSerif = [sansSerif.name];
        monospace = [monospace.name];
        emoji = [emoji.name];
      };
    };

    home.file.".config/fontconfig/conf.d/20-family-fallbacks.conf" = {
      enable = true;

      text = ''
        <?xml version='1.0'?>
        <!DOCTYPE fontconfig SYSTEM 'urn:fontconfig:fonts.dtd'>
        <fontconfig>

        ${configContent}
        </fontconfig>
      '';
    };
  };
}
