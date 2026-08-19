# services.flaresolverr — solve Cloudflare challenges on behalf of other services.
#
# A small HTTP proxy that drives a real headless browser: a client hands it a
# URL, it loads the page, waits out the interstitial, and returns the HTML plus
# the cf_clearance cookie. Suwayomi has first-class support for it (see
# server.flareSolverr* in services/suwayomi.nix); the *arr stack can use it too.
#
# This exists because the alternative here is worse. Suwayomi can embed its own
# Chromium (KCEF/JCEF) for the same job, and this fleet ran that for a while
# under a buildFHSEnv plus xvfb-run wrapper. On the 2.3 upgrade it stopped
# linking — `libcef.so: libglib-2.0.so.0: cannot open shared object file` — and
# the server crashlooped at startup, taking the whole service down rather than
# just the bypass. That is the shape of the problem: an in-process browser makes
# a browser bug a service outage, and it puts 519 MB of downloaded Chromium in a
# state directory where nothing declarative can see it.
#
# Out of process, a crash here costs a failed chapter fetch and nothing else.
#
# Loopback only. openFirewall stays false and the port is deliberately absent
# from cosmos.services.netbird.client.exposedPorts, because this is an
# unauthenticated endpoint that fetches arbitrary URLs on request — an SSRF
# primitive for anyone who can reach it. The only client is on this host.
#
# Stateless by design, so nothing is persisted and nothing is backed up. The
# upstream module's DynamicUser is fine precisely because it pairs with
# RuntimeDirectory rather than StateDirectory — that pairing is what broke
# crowdsec here (see the comment in services/crowdsec.nix), and it is absent.
{...}: {
  den.aspects.services.flaresolverr.nixos = {
    config,
    lib,
    ...
  }: let
    inherit (lib.options) mkOption;
    inherit (lib.types) port;

    cfg = config.cosmos.services.flaresolverr;
  in {
    options.cosmos.services.flaresolverr = {
      port = mkOption {
        type = port;
        default = 8191;
        description = ''
          Where FlareSolverr listens.

          Upstream's default. Free on every host in the fleet, and unlike 8080
          — which suwayomi already owns on endeavour — there is nothing else
          competing for it.
        '';
      };
    };

    config = {
      services.flaresolverr = {
        enable = true;
        inherit (cfg) port;
        # Never. See the header: this endpoint will fetch any URL it is given,
        # without authentication.
        openFirewall = false;
      };
    };
  };
}
