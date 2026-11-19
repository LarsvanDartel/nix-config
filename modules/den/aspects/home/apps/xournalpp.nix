# home.xournalpp — handwritten notes and PDF annotation with the stylus
# (+ the defaultApplication option: owns its note formats, offered for PDFs).
{...}: {
  den.aspects.home.xournalpp.homeManager = {
    config,
    lib,
    pkgs,
    ...
  }: let
    inherit (lib.options) mkOption;
    inherit (lib.types) bool;
    inherit (lib.modules) mkIf;

    cfg = config.cosmos.programs.xournalpp;
    xournalpp = ["com.github.xournalpp.xournalpp.desktop"];
  in {
    options.cosmos.programs.xournalpp.defaultApplication = mkOption {
      type = bool;
      default = false;
    };

    config = {
      home.packages = [pkgs.xournalpp];
      cosmos.system.impermanence.persist.directories = [".config/xournalpp"];

      xdg.mimeApps = mkIf cfg.defaultApplication {
        enable = true;
        defaultApplications = {
          "application/x-xoj" = xournalpp;
          "application/x-xojpp" = xournalpp;
          "application/x-xopp" = xournalpp;
          "application/x-xopt" = xournalpp;
        };
        # Open-with only; home.zathura stays the PDF default.
        associations.added."application/pdf" = xournalpp;
      };
    };
  };
}
