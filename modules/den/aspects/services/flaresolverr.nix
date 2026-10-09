# services.flaresolverr — solve Cloudflare challenges for other services.
#
# Selenium removed `options.headless`, so chromium needs a real display —
# without one the renderer dies with "Unable to receive message from renderer".
# Hence ExecStart wrapped in xvfb-run (FlareSolverr's internal Xvfb path is
# never reached) and SystemCallFilter dropped (Xvfb needs @setuid and more).
#
# Loopback only, deliberately absent from netbird exposedPorts: an
# unauthenticated endpoint that fetches arbitrary URLs is an SSRF primitive.
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
        # Never — unauthenticated arbitrary-URL fetcher (SSRF); see header.
        openFirewall = false;
      };

      systemd.services.flaresolverr.serviceConfig = {
        ExecStart =
          mkForce
          "${lib.getExe pkgs.xvfb-run} -a ${lib.getExe config.services.flaresolverr.package}";
        SystemCallFilter = mkForce [];
      };
    };
  };
}
