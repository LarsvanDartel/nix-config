# services.site — lvdar.nl, the personal website and blog.
#
# Nothing persisted on purpose: an impermanence entry under /var/lib/private
# (DynamicUser) is the EBUSY that broke ntfy; the working copy is a cache.
{inputs, ...}: {
  flake-file.inputs.site.url = "git+https://tangled.org/lvdar.nl/site";

  den.aspects.services.site.nixos = {...}: {
    imports = [inputs.site.nixosModules.default];

    services.site = {
      enable = true;
      port = 3031;

      # 0.0.0.0: edgeTerminated, traffic arrives from gaia's netbird-proxy.
      address = "0.0.0.0";

      # The default would advertise localhost in feed and sitemap.
      baseUrl = "https://lvdar.nl";

      # Handled in-app: TLS ends on gaia, netbird-proxy forwards the original Host.
      redirectHost = "www.lvdar.nl";

      content = {
        # Must stay public: the DynamicUser has no git credentials.
        repository = "https://tangled.org/lvdar.nl/blog";
        branch = "main";

        interval = 60;

        # Hardcoded DID + knot layout: if pushes stop publishing within a
        # second, check this first.
        refPath = "/tank/git/did:plc:fpotkfjfgnqg2jiskgfcyjx5/refs/heads/main";
      };

      # Off: refPath covers it without a secret. Needed only if the site
      # moves off the knot host.
      refreshTokenFile = null;
    };
  };
}
