# home.thunderbird (+ the defaultApplication option; deployment sets it true)
{...}: {
  den.aspects.home.thunderbird.homeManager = {
    config,
    lib,
    ...
  }: let
    inherit (lib.options) mkOption;
    inherit (lib.types) bool;
    inherit (lib.modules) mkIf;

    cfg = config.cosmos.programs.thunderbird;
  in {
    options.cosmos.programs.thunderbird.defaultApplication = mkOption {
      type = bool;
      default = false;
    };

    config = {
      programs.thunderbird = {
        enable = true;
        profiles.default.isDefault = true;
      };

      cosmos.system.impermanence.persist.directories = [".thunderbird"];

      xdg.mimeApps = mkIf cfg.defaultApplication {
        enable = true;
        # Taken from thunderbird.desktop's own MimeType line. mailto matters
        # beyond tidiness: home.zen's setAsDefaultBrowser claims it too, so
        # without this a mailto: link opens the browser. These are plain
        # definitions and zen's are mkDefault, so these win.
        defaultApplications = let
          tb = ["thunderbird.desktop"];
        in {
          "x-scheme-handler/mailto" = tb;
          "message/rfc822" = tb;
          "text/calendar" = tb;
          "text/x-vcard" = tb;
        };
      };
    };
  };
}
