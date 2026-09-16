# services.node-exporter — host metrics, scraped over the mesh.
#
# In roles.server: endeavour, gaia, pioneer — not voyager, a sleeping laptop
# would sit permanently "target down". Cheap enough for the Pi: no local
# writes, so it does not touch pioneer's SD card.
{den, ...}: {
  den.aspects.services.node-exporter = {
    includes = [den.aspects.services.netbird.client];

    nixos = {
      config,
      lib,
      ...
    }: let
      inherit (lib.options) mkOption;
      inherit (lib.types) port listOf str;

      cfg = config.cosmos.services.node-exporter;
    in {
      options.cosmos.services.node-exporter = {
        port = mkOption {
          type = port;
          default = 9500;
          description = ''
            Not 9100, which is node_exporter's conventional port and would be
            the obvious choice.

            OpenCloud on endeavour is not one service on one port: it is a
            constellation of internal services occupying most of 9091-9304,
            including 9100 on loopback. node_exporter binds 0.0.0.0, so the
            two collide and the exporter dies with "address already in use" —
            on that host only, which makes it exactly the sort of thing that
            passes review and fails on deploy.

            9500 is clear on every host: endeavour has nothing between 9304
            and 9696, gaia holds 9090/9091/9100/9444, pioneer holds nothing.
            Uniform across the fleet so the scrape config stays one line.
          '';
        };

        collectors = mkOption {
          type = listOf str;
          default = ["systemd"];
          description = ''
            Collectors to enable on top of the built-in defaults.

            `systemd` is the one that earns its keep: it exports
            node_systemd_unit_state per unit, which is what turns "a service is
            dead" into something queryable and alertable. The push
            notifications from core.notify-failure catch the *transition*; this
            catches the state, so a unit that was already dead before the
            monitoring existed is still visible.
          '';
        };
      };

      config = {
        services.prometheus.exporters.node = {
          enable = true;
          inherit (cfg) port;
          enabledCollectors = cfg.collectors;

          # 0.0.0.0 firewalled to the mesh, like kanidm and the arrs: the mesh
          # address is assigned by NetBird at enrollment, unknown at eval time.
          openFirewall = false;
        };

        # Mesh-only reach; otherwise the scrape times out silently instead of
        # failing loudly.
        cosmos.services.netbird.client.exposedPorts = [cfg.port];
      };
    };
  };
}
