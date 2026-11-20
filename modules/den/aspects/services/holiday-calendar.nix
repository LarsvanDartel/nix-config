# services.holiday-calendar — daily mirror of Dutch holiday ICS feeds into a Stalwart calendar, which cannot subscribe itself.
{den, ...}: {
  den.aspects.services.holiday-calendar = {
    includes = [den.aspects.services.stalwart];

    nixos = {
      config,
      lib,
      pkgs,
      ...
    }: let
      stalwart = config.cosmos.services.stalwart;
      account = "lvdar@${stalwart.domain}";

      settings = pkgs.writeText "holiday-calendar.json" (builtins.toJSON {
        # The recovery admin impersonates the owner on the loopback listener,
        # so no credential of the owner's lands on the server.
        user = "${account}%${config.services.stalwart.admin.username}";
        calendar = "http://127.0.0.1:${toString stalwart.adminPort}/dav/cal/${lib.escapeURL account}/feestdagen/";
        name = "Feestdagen & schoolvakanties";
        feeds =
          [
            {
              # The description's first line tells holidays from observances.
              url = "https://calendar.google.com/calendar/ical/nl.dutch%23holiday%40group.v.calendar.google.com/public/basic.ics";
              region = null;
              description = true;
            }
          ]
          ++ map (region: {
            url = "https://agenda-abonnement.nl/schoolvakanties${region}nederland.ics";
            inherit region;
            description = false;
          }) ["noord" "midden" "zuid"];
        # Where this region's advised spring holiday misses carnaval, the week around it is added.
        carnavalRegion = "zuid";
      });

      sync = pkgs.writers.writePython3Bin "holiday-calendar" {
        libraries = with pkgs.python3Packages; [icalendar python-dateutil];
      } (builtins.readFile ./_holiday-calendar.py);
    in {
      systemd.services.holiday-calendar = {
        description = "Mirror holiday feeds into a Stalwart calendar";
        after = ["stalwart.service" "network-online.target"];
        wants = ["network-online.target"];

        serviceConfig = {
          Type = "oneshot";
          DynamicUser = true;
          ExecStart = "${lib.getExe sync} ${settings}";
          LoadCredential = ["admin:${config.sops.secrets."keys/stalwart/admin".path}"];
        };
      };

      systemd.timers.holiday-calendar = {
        description = "Daily holiday feed mirror";
        wantedBy = ["timers.target"];
        timerConfig = {
          OnCalendar = "daily";
          RandomizedDelaySec = "1h";
          Persistent = true;
        };
      };
    };
  };
}
