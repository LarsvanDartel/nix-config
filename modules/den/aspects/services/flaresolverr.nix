# services.flaresolverr — solve Cloudflare challenges for other services.
#
# The upstream module cannot run headless: Selenium removed `options.headless`,
# so FlareSolverr's request for a headless browser is a silent no-op and
# chromium wants a real display — the renderer dies with "Unable to receive
# message from renderer", which reads like a browser bug. That is also why it
# works on voyager and in the nixpkgs VM test but failed here: the display,
# nothing else (versions, hardening, cores and GPUs were all eliminated).
#
# Two overrides on top of the module:
#
#   * ExecStart wrapped in xvfb-run. FlareSolverr's own internal Xvfb only
#     starts on a path this configuration never reaches.
#   * SystemCallFilter dropped: Xvfb needs several denied groups (@setuid
#     trips it first, more behind it). Acceptable for a DynamicUser with no
#     state and no network exposure; the module's other hardening is kept.
#
# Loopback only, deliberately absent from netbird exposedPorts: an
# unauthenticated endpoint that fetches arbitrary URLs is an SSRF primitive.
#
# Stateless; the DynamicUser is safe because it pairs with RuntimeDirectory,
# not StateDirectory — the pairing that broke crowdsec (services/crowdsec.nix).
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
