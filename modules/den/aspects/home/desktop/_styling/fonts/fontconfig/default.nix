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

  installedFonts = map (font: config.cosmos.desktops.common.styling.fonts.pkgs.${font}) config.cosmos.desktops.common.styling.fonts.installed;

  configContent = concatStrings (map aliasConfig installedFonts);

  # A pixel font is only crisp at multiples of its grid: round every requested pixel
  # size down to one (at least one grid). Pango sizes the layout from the edited
  # pattern, so measurement and rendering both see the snapped size.
  pixelGridConfig = font: let
    grid = "<double>${toString font.pixelGrid}</double>";
  in ''
    <match target="pattern">
      <test name="family" qual="any"><string>${font.name}</string></test>
      <test name="pixelsize" compare="less">${grid}</test>
      <edit name="pixelsize" mode="assign">${grid}</edit>
    </match>
    <match target="pattern">
      <test name="family" qual="any"><string>${font.name}</string></test>
      <edit name="pixelsize" mode="assign">
        <times><floor><divide><name>pixelsize</name>${grid}</divide></floor>${grid}</times>
      </edit>
    </match>
  '';

  # A bold cut in its own family is never picked for a bold request, so fontconfig
  # smears the regular one (embolden). Point bold at that family, at the weight it has.
  boldFamilyConfig = font: ''
    <match target="pattern">
      <test name="family" qual="any"><string>${font.name}</string></test>
      <test name="weight" compare="more_eq"><const>bold</const></test>
      <edit name="family" mode="prepend" binding="strong"><string>${font.boldFamily}</string></edit>
      <edit name="weight" mode="assign"><const>medium</const></edit>
    </match>
  '';

  pixelFontContent =
    concatStrings (map pixelGridConfig (builtins.filter (font: font.pixelGrid != null) installedFonts))
    + concatStrings (map boldFamilyConfig (builtins.filter (font: font.boldFamily != null) installedFonts));
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

    home.file.".config/fontconfig/conf.d/30-pixel-fonts.conf".text = ''
      <?xml version='1.0'?>
      <!DOCTYPE fontconfig SYSTEM 'urn:fontconfig:fonts.dtd'>
      <fontconfig>
      ${pixelFontContent}
      </fontconfig>
    '';
  };
}
