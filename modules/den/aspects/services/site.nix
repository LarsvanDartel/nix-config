# services.site — lvdar.nl, the personal website and blog.
#
# Content lives in its own repository, polled and recompiled on revision move
# — publishing is a push, not a deploy. Nothing is persisted on purpose: a
# StateDirectory under DynamicUser lands in /var/lib/private, where an
# impermanence entry is the EBUSY that broke ntfy, crowdsec and tile-traccar;
# the working copy is a CacheDirectory and a reclone is cheap.
{inputs, ...}: {
  flake-file.inputs.site.url = "git+https://tangled.org/lvdar.nl/site";

  den.aspects.services.site.nixos = {...}: {
    imports = [inputs.site.nixosModules.default];

    services.site = {
      enable = true;
      port = 3031;

      # 0.0.0.0, not loopback: edgeTerminated — connections arrive from gaia's
      # netbird-proxy over WireGuard. The firewall limits reach (exposedPorts
      # in hosts/endeavour.nix).
      address = "0.0.0.0";

      # Feed and sitemap must emit absolute URLs and learn the public name
      # nowhere else; the default would advertise localhost.
      baseUrl = "https://lvdar.nl";

      # Handled in-app because no proxy remains by the time a request arrives
      # (TLS ends on gaia); netbird-proxy forwards the original Host header,
      # so the middleware sees the browser's name.
      redirectHost = "www.lvdar.nl";

      content = {
        # Public on purpose: the DynamicUser has no keys or known_hosts and
        # git runs with GIT_TERMINAL_PROMPT=0, so making it private fails
        # loudly on the next poll instead of hanging.
        repository = "https://tangled.org/lvdar.nl/blog";
        branch = "main";

        # Ceiling on staleness only — refPath below publishes in ~1s; a
        # same-revision poll costs one shallow fetch, so this is nearly free.
        interval = 60;

        # The blog's ref file on the knot (same host, so the systemd.path is
        # an inotify watch, not a network call; no credential, no port). The
        # DID and the knot's on-disk layout are hardcoded and knowable from
        # nowhere else: if a push stops publishing within a second, check this
        # first; the poll above still catches it within a minute.
        refPath = "/tank/git/did:plc:fpotkfjfgnqg2jiskgfcyjx5/refs/heads/main";
      };

      # POST /api/refresh left off: refPath publishes within a second with no
      # secret, open endpoint or rotation. Only earns its keep if the site
      # moves off the knot host — see the option docs.
      refreshTokenFile = null;
    };
  };
}
