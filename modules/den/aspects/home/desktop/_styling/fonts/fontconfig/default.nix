# home.styling — fontconfig family fallbacks and pixel-font size snapping.
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

  # Snaps the bold family too: foot requests it by name. The file must sort after home-manager's
  # 52-hm-default-fonts.conf, or a `monospace` request doesn't name the pixel font yet.
  pixelGridConfig = font: let
    grid = "<double>${toString font.pixelGrid}</double>";
    snap = family: ''
      <match target="pattern">
        <test name="family" qual="any"><string>${family}</string></test>
        <test name="pixelsize" compare="less">${grid}</test>
        <edit name="pixelsize" mode="assign">${grid}</edit>
      </match>
      <match target="pattern">
        <test name="family" qual="any"><string>${family}</string></test>
        <edit name="pixelsize" mode="assign">
          <times><floor><divide><name>pixelsize</name>${grid}</divide></floor>${grid}</times>
        </edit>
      </match>
    '';
  in
    concatStrings (map snap (lib.unique ([font.name] ++ lib.optional (font.boldFamily != null) font.boldFamily)));

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

    home.file.".config/fontconfig/conf.d/55-pixel-fonts.conf".text = ''
      <?xml version='1.0'?>
      <!DOCTYPE fontconfig SYSTEM 'urn:fontconfig:fonts.dtd'>
      <fontconfig>
      ${pixelFontContent}
      </fontconfig>
    '';
  };
}
