# services.site — lvdar.nl, the personal website and blog.
#
# Stateless by construction: the posts are Typst, compiled to HTML when the
# package is built, so the running service is a binary full of static strings.
# There is nothing under /var/lib to persist and nothing to add to restic —
# which is why, unlike services/typstnique.nix, this aspect declares no
# impermanence path at all.
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
    };
  };
}
