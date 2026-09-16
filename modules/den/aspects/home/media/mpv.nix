# home.mpv (+ the defaultApplication option; deployment sets it true)
{...}: {
  den.aspects.home.mpv.homeManager = {
    config,
    lib,
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
      programs.mpv.enable = true;

      xdg.mimeApps = mkIf cfg.defaultApplication {
        enable = true;
        # A curated subset, not mpv.desktop's full ~80 entries: reading the
        # MimeType from the package would be import-from-derivation, forcing
        # mpv to build during every host's evaluation. Missed containers
        # still open from mpv itself.
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
