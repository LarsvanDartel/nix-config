{
  lib,
  config,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;
  inherit (lib.strings) concatStrings;

  cfg = config.styling.fonts.fontconfig;

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
      font: aliasConfig config.styling.fonts.pkgs.${font}
    )
    config.styling.fonts.installed
  );
in {
  options.styling.fonts.fontconfig = {
    enable = mkEnableOption "fontconfig";
  };

  options.systemwide.fontconfig = {
    enable = mkEnableOption "fontconfig";
  };

  config = mkIf cfg.enable {
    systemwide.fontconfig.enable = true;

    fonts.fontconfig = {
      enable = true;

      defaultFonts = {
        serif = [config.styling.fonts.serif.name];
        sansSerif = [config.styling.fonts.sansSerif.name];
        monospace = [config.styling.fonts.monospace.name];
        emoji = [config.styling.fonts.emoji.name];
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
