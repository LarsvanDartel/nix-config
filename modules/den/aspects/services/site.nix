# services.site — lvdar.nl, the personal website and blog.
#
# Nothing persisted on purpose: an impermanence entry under /var/lib/private
# (DynamicUser) is the EBUSY that broke ntfy; the working copy is a cache.
{inputs, ...}: let
  # services.site.port and the netbird-service target. hosts/gaia.nix's
  # lvdar.nl localVhost also points here, as an address it must spell out.
  port = 3031;
in {
  flake-file.inputs.site.url = "git+https://tangled.org/lvdar.nl/site";

  # www only: the apex can't be a proxy service (management 422s
  # non-subdomains, masked by the reconciler as "already taken"); gaia
  # serves it via netbird.localVhosts. The app 301s www to the apex.
  den.aspects.services.site.netbird-service = {host, ...}: {
    www = {
      bearerAuth.enable = false;
      targets = [
        {
          peer = host.name;
          inherit port;
        }
      ];
    };
  };

  den.aspects.services.site.nixos = {...}: {
    imports = [inputs.site.nixosModules.default];

    cosmos.services.netbird.client.exposedPorts = [port];

    services.site = {
      enable = true;
      inherit port;

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
        refPath = "/tank/knot/repos/plc/fp/otkfjfgnqg2jiskgfcyjx5/refs/heads/main";
      };

      # Off: refPath covers it without a secret. Needed only if the site
      # moves off the knot host.
      refreshTokenFile = null;
    };
  };
}
