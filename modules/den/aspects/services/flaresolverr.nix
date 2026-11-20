# services.flaresolverr — solves Cloudflare challenges for other services, on loopback only.
{...}: {
  den.aspects.services.flaresolverr.nixos = {
    config,
    lib,
    pkgs,
    ...
  }: let
    inherit (lib.options) mkOption;
    inherit (lib.modules) mkForce;
    inherit (lib.types) port;

    cfg = config.cosmos.services.flaresolverr;
  in {
    options.cosmos.services.flaresolverr = {
      port = mkOption {
        type = port;
        default = 8191;
        description = ''
          Where FlareSolverr listens.

          Upstream's default, and free on every host in the fleet — unlike 8080,
          which suwayomi already owns on endeavour.
        '';
      };
    };

    config = {
      services.flaresolverr = {
        enable = true;
        inherit (cfg) port;
        # Never, nor netbird exposedPorts: an unauthenticated arbitrary-URL fetcher is an SSRF primitive.
        openFirewall = false;
      };

      # Selenium dropped headless mode, so chromium needs a display: xvfb-run (FlareSolverr's own Xvfb path
      # is never reached), and no SystemCallFilter since Xvfb needs @setuid and more.
      systemd.services.flaresolverr.serviceConfig = {
        ExecStart =
          mkForce
          "${lib.getExe pkgs.xvfb-run} -a ${lib.getExe config.services.flaresolverr.package}";
        SystemCallFilter = mkForce [];
      };
    };
  };
}
