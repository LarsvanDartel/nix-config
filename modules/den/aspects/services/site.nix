# services.site — lvdar.nl, the personal website and blog.
#
# The content is not in this flake. Posts live in their own repository, which
# the service polls and recompiles when the revision moves, so publishing a post
# is a push rather than a deploy — it does not wait for flake-bump, build-gate
# and comin. Only the site's *code* comes through the input below.
#
# Nothing here needs persisting. The git working copy is a CacheDirectory, and
# deliberately so: under DynamicUser a StateDirectory lands in /var/lib/private,
# and an impermanence entry over that path is the EBUSY that has already broken
# ntfy, crowdsec and tile-traccar on this fleet. Losing the checkout on reboot
# costs one clone of a few hundred kilobytes.
{inputs, ...}: {
  flake-file.inputs.site.url = "git+https://tangled.org/lvdar.nl/site";

  den.aspects.services.site.nixos = {...}: {
    imports = [inputs.site.nixosModules.default];

    services.site = {
      enable = true;
      port = 3031;

      # Bound to the mesh rather than loopback: this host is edgeTerminated, so
      # the connection arrives from gaia's netbird-proxy over WireGuard and a
      # loopback bind would refuse it. The firewall is what limits reach — 3031
      # is opened on the netbird interface alone, in hosts/endeavour.nix.
      address = "0.0.0.0";

      # Not cosmetic. The Atom feed and the sitemap have to emit absolute URLs
      # and have no other way to learn what the outside world calls this host;
      # left at its default the feed would advertise localhost to every reader.
      baseUrl = "https://lvdar.nl";

      # Handled in the application because nothing local can do it: TLS is
      # terminated on gaia, so by the time a request is here there is no proxy
      # left between it and the browser. netbird-proxy forwards the original
      # Host header (pass_host_header defaults on for http services), so the
      # name the middleware matches is the one the browser sent.
      redirectHost = "www.lvdar.nl";

      content = {
        # Public over HTTPS on purpose. The service runs as a DynamicUser with
        # no keys and no known_hosts, and git is invoked with
        # GIT_TERMINAL_PROMPT=0 — so were this ever made private it would fail
        # loudly on the next poll rather than hang waiting for a password.
        repository = "https://tangled.org/lvdar.nl/blog";
        branch = "main";

        # A poll that finds the same revision costs one shallow fetch and skips
        # the compile entirely, so this is cheap to run often. It is also the
        # ceiling on how stale the site can be, since refreshTokenFile below is
        # unset and nothing pushes at us.
        interval = 60;
      };

      # POST /api/refresh publishes immediately instead of waiting up to
      # `interval`. It stays off until there is a secret to gate it with: an
      # unauthenticated endpoint that runs a git fetch and a Typst compile on
      # demand is a free way to load the box.
      #
      # To turn it on, add a key to nix-secrets and point this at it:
      #   sops.secrets."keys/site/refresh-token".sopsFile = ...;
      #   refreshTokenFile = config.sops.secrets."keys/site/refresh-token".path;
      # then have the knot's post-receive hook curl the endpoint with it.
      refreshTokenFile = null;
    };
  };
}
