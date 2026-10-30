# home.mpv (+ the defaultApplication option; deployment sets it true)
{...}: {
  den.aspects.home.mpv.homeManager = {
    config,
    lib,
    pkgs,
    ...
  }: let
    inherit (lib.options) mkOption;
    inherit (lib.types) bool;
    inherit (lib.modules) mkIf;

    cfg = config.cosmos.programs.mpv;
  in {
    options.cosmos.programs.mpv.defaultApplication = mkOption {
      type = bool;
      default = false;
    };

    config = {
      programs.mpv = {
        enable = true;
        # uosc replaces the built-in OSC: large touch targets.
        scripts = with pkgs.mpvScripts; [uosc thumbfast];
        config = {
          osc = "no";
          osd-bar = "no";
        };
      };

      xdg.mimeApps = mkIf cfg.defaultApplication {
        enable = true;
        # Curated subset: reading mpv.desktop's MimeType would be IFD.
        defaultApplications = let
          mpv = ["mpv.desktop"];
        in {
          "video/mp4" = mpv;
          "video/x-matroska" = mpv;
          "video/webm" = mpv;
          "video/quicktime" = mpv;
          "video/x-msvideo" = mpv;
          "video/mpeg" = mpv;
          "video/ogg" = mpv;
          "video/x-flv" = mpv;
          "video/3gpp" = mpv;

          "audio/mpeg" = mpv;
          "audio/flac" = mpv;
          "audio/ogg" = mpv;
          "audio/x-vorbis+ogg" = mpv;
          "audio/x-opus+ogg" = mpv;
          "audio/wav" = mpv;
          "audio/x-wav" = mpv;
          "audio/mp4" = mpv;
          "audio/aac" = mpv;
          "audio/x-m4a" = mpv;
        };
      };
    };
  };
}
