# services.node-exporter — host metrics, scraped over the mesh.
#
# In roles.server, so it lands on endeavour, gaia and pioneer and not on
# voyager. A laptop that is asleep half the day is not a monitoring target: it
# would sit permanently in "target down", which trains you to ignore the one
# alert that means a server has actually gone away.
#
# Cheap enough for the Pi — a few tens of MB resident, no local writes, so it
# does not touch pioneer's SD card, which is the constraint that keeps the log
# shipper off that host.
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
          default = 9100;
          description = "The conventional node_exporter port.";
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

          # Left on 0.0.0.0 and firewalled to the mesh interface instead, the
          # same shape as kanidm and the arrs here. Binding to the mesh address
          # is not possible at eval time — NetBird assigns it at enrollment.
          openFirewall = false;
        };

        # Reachable from the mesh and nowhere else. Without this the scrape
        # times out rather than failing loudly, per the warning on the option.
        cosmos.services.netbird.client.exposedPorts = [cfg.port];
      };
    };
  };
}
