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
        # A curated subset, not mpv.desktop's full ~80 entries. Reading the
        # MimeType line out of the package would keep the two in sync, but that
        # is import-from-derivation — it would force mpv to build during
        # evaluation of every host. These are the containers that actually turn
        # up; anything missed still opens from mpv itself.
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
