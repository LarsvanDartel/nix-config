# services.flaresolverr — solve Cloudflare challenges for other services.
#
# A small HTTP proxy that drives a real browser: hand it a URL, it loads the
# page, waits out the interstitial and returns the HTML plus the cf_clearance
# cookie. Suwayomi has first-class support (server.flareSolverr* in
# services/suwayomi.nix); the *arr stack can use it too.
#
# The upstream module alone does not work on a headless machine, and the reason
# is worth writing down because nothing about the error says it. FlareSolverr
# asks Selenium for a headless browser, but modern Selenium removed the
# `options.headless` property, so that request is silently a no-op and chromium
# is launched wanting a real display. On a desktop it quietly borrows the
# session's; on a server there is none, the renderer dies immediately, and what
# surfaces is "Unable to receive message from renderer" — which reads like a
# browser bug rather than a missing X server.
#
# That is why this works on voyager and in the nixpkgs VM test but failed here:
# not versions, not hardening, not the 72 cores, not the GPUs. All of those were
# tested and eliminated. It is the display.
#
# So two overrides on top of the official module:
#
#   * ExecStart is wrapped in xvfb-run, giving chromium a display to draw into.
#     FlareSolverr does start its own Xvfb internally, but only on a path this
#     configuration never reaches — without the wrapper it still dies, checked.
#   * SystemCallFilter is dropped. Xvfb needs several of the groups the module
#     denies: @setuid trips it first with SIGSYS, and removing only that one
#     leaves "Xvfb display did not open" from another. Bisecting the remaining
#     thirteen was not worth it against a service that already runs as a
#     DynamicUser with no state and no network exposure.
#
# Everything else the module hardens is kept and verified working: PrivateUsers,
# PrivateDevices, ProtectHome, ProtectProc, RestrictNamespaces, RestrictRealtime
# and the capability bounding set.
#
# Loopback only. openFirewall stays false and the port is deliberately absent
# from cosmos.services.netbird.client.exposedPorts, because this is an
# unauthenticated endpoint that fetches arbitrary URLs on request — an SSRF
# primitive for anything that can reach it. The only client is on this host.
#
# Stateless, so nothing is persisted and nothing is backed up. The module's
# DynamicUser is safe here precisely because it pairs with RuntimeDirectory
# rather than StateDirectory — that pairing is what broke crowdsec on this
# fleet (see services/crowdsec.nix), and it is absent.
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
        # Never. See the header: this endpoint fetches any URL it is given,
        # without authentication.
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
