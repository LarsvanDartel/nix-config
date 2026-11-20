# services.birthday-calendar — the birthdays in lvdar's Stalwart address
# books, mirrored hourly into one Stalwart calendar as yearly events.
{den, ...}: {
  den.aspects.services.birthday-calendar = {
    includes = [den.aspects.services.stalwart];

    nixos = {
      config,
      lib,
      pkgs,
      ...
    }: let
      stalwart = config.cosmos.services.stalwart;
      account = "lvdar@${stalwart.domain}";
      dav = "http://127.0.0.1:${toString stalwart.adminPort}/dav";

      settings = pkgs.writeText "birthday-calendar.json" (builtins.toJSON {
        # As in services.holiday-calendar: the recovery admin impersonating
        # the owner, on the loopback management listener.
        user = "${account}%${config.services.stalwart.admin.username}";
        # Every address book under this home is read.
        addressBooks = "${dav}/card/${lib.escapeURL account}/";
        calendar = "${dav}/cal/${lib.escapeURL account}/verjaardagen/";
        name = "Verjaardagen";
      });

      sync = pkgs.writers.writePython3Bin "birthday-calendar" {
        libraries = [pkgs.python3Packages.icalendar];
      } (builtins.readFile ./_birthday-calendar.py);
    in {
      systemd.services.birthday-calendar = {
        description = "Mirror contact birthdays into a Stalwart calendar";
        after = ["stalwart.service"];

        serviceConfig = {
          Type = "oneshot";
          DynamicUser = true;
          ExecStart = "${lib.getExe sync} ${settings}";
          LoadCredential = ["admin:${config.sops.secrets."keys/stalwart/admin".path}"];
        };
      };

      systemd.timers.birthday-calendar = {
        description = "Hourly contact birthday mirror";
        wantedBy = ["timers.target"];
        timerConfig = {
          OnCalendar = "hourly";
          RandomizedDelaySec = "10min";
          Persistent = true;
        };
      };
    };
  };
}
