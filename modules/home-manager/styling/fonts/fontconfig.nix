{
  lib,
  config,
  ...
}: let
  cfg = config.modules.styling.fonts.fontconfig;

  aliasConfig = font: ''
    <alias>
      <family>${font.name}</family>

      <prefer>
        <family>${font.name}</family>
    ${lib.concatStrings (map (font: "    <family>${font}</family>\n") font.fallbackFonts)}
      </prefer>
    </alias>
  '';

  configContent = lib.concatStrings (
    map (
      font: aliasConfig config.modules.styling.fonts.pkgs.${font}
    )
    config.modules.styling.fonts.installed
  );
in {
  options.modules.styling.fonts.fontconfig = {
    enable = lib.mkEnableOption "fontconfig";
  };

  config = lib.mkIf cfg.enable {
    fonts.fontconfig = {
      enable = true;

      defaultFonts = {
        serif = [config.modules.styling.fonts.serif.name];
        sansSerif = [config.modules.styling.fonts.sansSerif.name];
        monospace = [config.modules.styling.fonts.monospace.name];
        emoji = [config.modules.styling.fonts.emoji.name];
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
