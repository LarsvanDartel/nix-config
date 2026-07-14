{...}: {
  flake.modules.homeManager.zathura = {
    config,
    lib,
    pkgs,
    ...
  }: let
    inherit (lib.options) mkOption;
    inherit (lib.types) bool;
    inherit (lib.modules) mkIf;

    cfg = config.cosmos.programs.zathura;

    # The default package only ships the PDF plugin; add the comic-book (cb)
    # plugin so zathura can open .cbz/.cbr files. zathura keys its mimetype
    # registry by canonical type, so the cb plugin's legacy "application/x-cbz"
    # already covers the "application/vnd.comicbook+zip" that glib reports.
    zathuraWithPlugins = pkgs.zathura.override {
      plugins = with pkgs.zathuraPkgs; [zathura_pdf_mupdf zathura_cb];
    };

    # zathura-cb renders archive pages via gdk-pixbuf and only treats entries
    # whose extension matches an available loader as pages. Manga downloads (e.g.
    # from Suwayomi) are usually WebP, which has no loader by default, so the
    # document ends up with zero pages (blank). Wrap zathura with a pixbuf cache
    # that includes the WebP (and SVG) loaders.
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
    options.cosmos.programs.zathura = {
      defaultApplication = mkOption {
        type = bool;
        default = false;
      };
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
