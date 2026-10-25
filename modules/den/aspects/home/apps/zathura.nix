# home.zathura — zathura (pdf + comic books) as a nix-wrapper-modules package
# (`nix run .#zathura`); the wrapper holds the config, home-manager installs it.
# webp/svg pages need nothing here: nixpkgs' zathura sets its own
# GDK_PIXBUF_MODULE_FILE (with both), overriding any we pass.
{
  inputs,
  cosmosStyling,
  ...
}: let
  mkZathura = pkgs: let
    colors = cosmosStyling.colors pkgs;
    channels = c: "${colors."${c}-rgb-r"}, ${colors."${c}-rgb-g"}, ${colors."${c}-rgb-b"}";
    rgb = c: "rgb(${channels c})";
    rgba = c: alpha: "rgba(${channels c}, ${toString alpha})";
  in
    inputs.nix-wrapper-modules.wrappers.zathura.wrap {
      inherit pkgs;
      plugins = with pkgs.zathuraPkgs; [zathura_pdf_mupdf zathura_cb];
      settings = {
        window-title-basename = true;
        selection-clipboard = "clipboard";

        # stylix's zathura target (base16-zathura).
        default-bg = rgba "base00" cosmosStyling.opacity.applications;
        default-fg = rgb "base01";
        statusbar-fg = rgb "base04";
        statusbar-bg = rgb "base02";
        inputbar-bg = rgb "base00";
        inputbar-fg = rgb "base07";
        notification-bg = rgb "base00";
        notification-fg = rgb "base07";
        notification-error-bg = rgb "base00";
        notification-error-fg = rgb "base08";
        notification-warning-bg = rgb "base00";
        notification-warning-fg = rgb "base08";
        highlight-color = rgba "base0A" 0.5;
        highlight-active-color = rgba "base0D" 0.5;
        completion-bg = rgb "base01";
        completion-fg = rgb "base0D";
        completion-highlight-fg = rgb "base07";
        completion-highlight-bg = rgb "base0D";
        recolor-lightcolor = rgb "base00";
        recolor-darkcolor = rgb "base06";
      };
    };
in {
  perSystem = {pkgs, ...}: {packages.zathura = mkZathura pkgs;};

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
  in {
    options.cosmos.programs.zathura.defaultApplication = mkOption {
      type = bool;
      default = false;
    };

    config = {
      home.packages = [(mkZathura pkgs)];
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
