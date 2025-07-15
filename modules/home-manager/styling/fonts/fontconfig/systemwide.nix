{
  fontconfig = {
    fonts.fontconfig = {
      enable = true;
      includeUserConf = true;

      allowBitmaps = true;
      useEmbeddedBitmaps = true;

      antialias = true;

      hinting = {
        enable = true;
        style = "full";
        autohint = true;
      };

      subpixel = {
        rgba = "rgb";
        lcdfilter = "default";
      };
    };
  };
}
