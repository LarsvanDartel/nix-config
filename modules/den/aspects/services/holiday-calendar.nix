# services.holiday-calendar — Dutch public holidays, observances and every
# region's school holidays, mirrored daily from public ICS feeds into one
# Stalwart calendar, which cannot subscribe to feeds itself.
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
        # The recovery admin impersonating the owner (`<account>%<admin>`),
        # on the loopback management listener: no credential of the owner's
        # own lands on the server.
        user = "${account}%${config.services.stalwart.admin.username}";
        calendar = "http://127.0.0.1:${toString stalwart.adminPort}/dav/cal/${lib.escapeURL account}/feestdagen/";
        name = "Feestdagen & schoolvakanties";
        feeds =
          [
            {
              # Public holidays and observances; the description's first
              # line tells them apart ("Officiële feestdag" or "Viering").
              url = "https://calendar.google.com/calendar/ical/nl.dutch%23holiday%40group.v.calendar.google.com/public/basic.ics";
              suffix = null;
              description = true;
            }
          ]
          ++ map (region: {
            url = "https://agenda-abonnement.nl/schoolvakanties${region}nederland.ics";
            suffix = region;
            description = false;
          }) ["noord" "midden" "zuid"];
      });

      sync = pkgs.writers.writePython3Bin "holiday-calendar" {
        libraries = [pkgs.python3Packages.icalendar];
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
