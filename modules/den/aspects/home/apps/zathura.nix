# home.zathura (with comic-book + webp support)
{...}: {
  den.aspects.home.zathura.homeManager = {
    config,
    lib,
    pkgs,
    ...
  }: let
    inherit (lib.options) mkOption;
    inherit (lib.types) bool;
    inherit (lib.modules) mkIf;

    cfg = config.cosmos.programs.zathura;

    zathuraWithPlugins = pkgs.zathura.override {
      plugins = with pkgs.zathuraPkgs; [zathura_pdf_mupdf zathura_cb];
    };

    pixbufCache = pkgs.gnome._gdkPixbufCacheBuilder_DO_NOT_USE {
      extraLoaders = with pkgs; [webp-pixbuf-loader librsvg];
    };

    zathuraPackage = pkgs.symlinkJoin {
      name = "zathura-with-webp";
      paths = [zathuraWithPlugins];
      nativeBuildInputs = [pkgs.makeWrapper];
      postBuild = ''
        rm $out/bin/zathura
        makeWrapper ${zathuraWithPlugins}/bin/zathura $out/bin/zathura \
          --set GDK_PIXBUF_MODULE_FILE ${pixbufCache}
      '';
    };
  in {
    options.cosmos.programs.zathura.defaultApplication = mkOption {
      type = bool;
      default = false;
    };

    config = {
      programs.zathura = {
        enable = true;
        package = zathuraPackage;
        options = {
          window-title-basename = true;
          selection-clipboard = "clipboard";
        };
      };
      xdg.mimeApps = mkIf cfg.defaultApplication {
        enable = true;
        defaultApplications = {
          "application/pdf" = ["org.pwmt.zathura.desktop"];
          "application/vnd.comicbook+zip" = ["org.pwmt.zathura.desktop"];
          "application/vnd.comicbook-rar" = ["org.pwmt.zathura.desktop"];
        };
      };
    };
  };
}
