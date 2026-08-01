# services.tile-traccar — feed Tile tracker locations into Traccar.
#
# Tile trackers have no GPS and no way to report anywhere but Tile's own
# cloud: a tag is found by whichever phone running the Tile app walks past it,
# and that phone uploads the fix. So this is a poller, not a receiver — it asks
# Tile where each tag was last seen and forwards that to Traccar's OsmAnd
# decoder, which is the one protocol that takes a plain HTTP request.
#
# Grown from a throwaway script (~/dev/python/main.py) into something that
# survives a reboot:
#
#   * one login for the life of the process rather than one per fetch. pytile
#     re-inits the session itself when it expires, and the client UUID is kept
#     on disk so Tile keeps seeing the same client instead of announcing a new
#     device sign-in every restart.
#   * a position is only forwarded when its timestamp moves. A tag reports
#     when someone walks past it, which at a 20s poll means the same fix would
#     otherwise be written to Traccar's history a few thousand times a day.
#   * localhost, not the published edge. The script posted to a public name,
#     which sent every fix out to gaia and back over WireGuard to reach a
#     decoder listening on this very host.
{den, ...}: {
  den.aspects.services.tile-traccar = {
    includes = [den.aspects.services.traccar];

    nixos = {
      config,
      lib,
      pkgs,
      ...
    }: let
      inherit (lib.options) mkOption mkEnableOption;
      inherit (lib.types) listOf str ints;

      cfg = config.cosmos.services.tile-traccar;
      traccar = config.cosmos.services.traccar;

      user = "tile-traccar";
      stateDir = "/var/lib/tile-traccar";

      python = pkgs.python3.withPackages (ps: with ps; [pytile aiohttp]);

      script = pkgs.writeText "tile-traccar.py" ''
        """Forward Tile tracker locations to Traccar's OsmAnd endpoint."""

        import asyncio
        import json
        import logging
        import os
        import sys
        import time
        import uuid as uuidlib
        from datetime import timezone
        from pathlib import Path
        from urllib.parse import urlencode

        from aiohttp import ClientError, ClientSession
        from pytile.api import async_login
        from pytile.errors import InvalidAuthError

        EMAIL = os.environ["TILE_EMAIL"]
        # systemd puts the sops secret here and nowhere else — not in the
        # environment, where anything that can read /proc could pick it up.
        PASSWORD = (
            (Path(os.environ["CREDENTIALS_DIRECTORY"]) / "tile-password").read_text().strip()
        )
        ENDPOINT = os.environ["TRACCAR_ENDPOINT"]
        INTERVAL = float(os.environ["POLL_INTERVAL"])
        DISCOVERY_INTERVAL = float(os.environ["DISCOVERY_INTERVAL"])
        IGNORED = set(json.loads(os.environ["IGNORED_TILES"]))
        MAX_AGE = float(os.environ["MAX_AGE"])
        CLIENT_UUID_FILE = Path(os.environ["CLIENT_UUID_FILE"])

        logging.basicConfig(format="%(message)s", level=logging.INFO, stream=sys.stdout)
        LOGGER = logging.getLogger("tile-traccar")


        def client_uuid() -> str:
            """Return this machine's Tile client id, minting one on first run.

            Tile treats an unknown client id as a new device signing in — mail to
            the account holder each time — so it has to outlive the process.
            """
            try:
                return CLIENT_UUID_FILE.read_text().strip()
            except FileNotFoundError:
                value = str(uuidlib.uuid4())
                CLIENT_UUID_FILE.write_text(value)
                return value


        async def report(session: ClientSession, tile) -> None:
            """POST one Tile's last known fix to Traccar."""
            # pytile hands back a naive datetime that is UTC; Traccar wants epoch
            # seconds, which sidesteps the question of how it would parse anything
            # else.
            timestamp = tile.last_timestamp.replace(tzinfo=timezone.utc)
            params = {
                "id": tile.uuid,
                "lat": tile.latitude,
                "lon": tile.longitude,
                "timestamp": int(timestamp.timestamp()),
            }
            if tile.altitude is not None:
                params["altitude"] = tile.altitude
            if tile.accuracy is not None:
                params["accuracy"] = tile.accuracy

            async with session.post(f"{ENDPOINT}/?{urlencode(params)}") as resp:
                if resp.status != 200:
                    # Traccar answers 400 for an id it has no device for, which is
                    # the expected state until one is created with the tag's uuid
                    # as its identifier. Worth saying out loud, with the uuid.
                    LOGGER.warning(
                        "Traccar refused %s (%s) with HTTP %s: %s",
                        tile.name,
                        tile.uuid,
                        resp.status,
                        (await resp.text()).strip(),
                    )
                else:
                    LOGGER.info(
                        "%s (%s) at %s, %s", tile.name, tile.uuid, tile.latitude, tile.longitude
                    )


        async def main() -> None:
            async with ClientSession() as session:
                api = await async_login(EMAIL, PASSWORD, session, client_uuid=client_uuid())
                LOGGER.info("Authenticated to Tile; polling every %ss", INTERVAL)

                tiles: dict = {}
                # Force discovery on the first pass.
                since_discovery = DISCOVERY_INTERVAL
                # uuid -> the timestamp last forwarded, so a fix is written once.
                reported: dict[str, int] = {}
                # uuid -> whether it was last seen as stale, to say so once.
                stale: dict[str, bool] = {}

                while True:
                    if since_discovery >= DISCOVERY_INTERVAL:
                        tiles = await api.async_get_tiles()
                        since_discovery = 0.0
                        LOGGER.debug("Discovered %d tile(s)", len(tiles))
                    else:
                        # Cheaper than re-listing: one request per tag, no account
                        # enumeration. New or removed tags are picked up by the
                        # discovery pass above.
                        await asyncio.gather(
                            *(tile.async_update() for tile in tiles.values()),
                            return_exceptions=True,
                        )

                    for uuid, tile in tiles.items():
                        if uuid in IGNORED or tile.last_timestamp is None:
                            continue
                        if tile.latitude is None or tile.longitude is None:
                            continue
                        stamp = int(tile.last_timestamp.replace(tzinfo=timezone.utc).timestamp())

                        # A tag has no clock and no radio of its own: the fix
                        # stands until some phone running the Tile app walks
                        # past it again. So an old timestamp does not mean the
                        # tag moved away — it means nobody has looked. Past
                        # MAX_AGE, take the position as no longer evidence of
                        # where the thing is now and stop restating it; Traccar
                        # keeps the last one it was given, so the map still
                        # shows where it was last actually seen.
                        age = time.time() - stamp
                        if MAX_AGE and age > MAX_AGE:
                            if not stale.get(uuid):
                                LOGGER.info(
                                    "%s (%s) last seen %.0f min ago; holding off",
                                    tile.name,
                                    tile.uuid,
                                    age / 60,
                                )
                                stale[uuid] = True
                            continue
                        if stale.pop(uuid, False):
                            LOGGER.info("%s (%s) is being seen again", tile.name, tile.uuid)

                        if reported.get(uuid) == stamp:
                            continue
                        try:
                            await report(session, tile)
                        except ClientError as err:
                            LOGGER.warning("Could not reach Traccar: %s", err)
                            continue
                        reported[uuid] = stamp

                    await asyncio.sleep(INTERVAL)
                    since_discovery += INTERVAL


        try:
            asyncio.run(main())
        except InvalidAuthError:
            # Nothing a retry fixes, so fail loudly rather than spin.
            LOGGER.error("Tile rejected the account in cosmos.services.tile-traccar.email")
            sys.exit(1)
      '';
    in {
      options.cosmos.services.tile-traccar = {
        enable =
          mkEnableOption "forwarding Tile tracker locations into Traccar"
          // {default = true;};

        email = mkOption {
          type = str;
          example = "someone@example.com";
          description = ''
            The Tile account to poll. Its password comes from the sops secret
            `keys/tile/password`, which is the whole of the credential — this
            is a normal account login, not an API token, so it is also the
            login to the app.
          '';
        };

        interval = mkOption {
          type = ints.positive;
          default = 20;
          description = ''
            Seconds between polls. Tile's own app refreshes on this order, and
            a fix is only forwarded when it changes, so a short interval costs
            requests to Tile rather than rows in Traccar.
          '';
        };

        discoveryInterval = mkOption {
          type = ints.positive;
          default = 900;
          description = ''
            Seconds between full re-listings of the account. Between them each
            known tag is refreshed individually — this is only how a tag added
            or removed in the app gets noticed.
          '';
        };

        maxAge = mkOption {
          type = ints.unsigned;
          default = 3600;
          description = ''
            Ignore a fix older than this many seconds, so that only a position
            something has actually been seen at recently is forwarded.

            A tag is passive: its last position persists in Tile's cloud until
            a phone running the app comes near it again, so a week-old fix
            reads exactly like a current one. That mostly matters on startup,
            when there is no record of what was already sent and the oldest
            fix on the account would otherwise be posted as news.

            Tile's own `is_lost` is deliberately not used for this. It marks a
            tag the account has given up on rather than one nobody has walked
            past, and a lost tag that someone finally does walk past is the
            one position worth having.

            0 disables the check.
          '';
        };

        ignoredTiles = mkOption {
          type = listOf str;
          default = [];
          example = ["p!fb79d495c0cb30211d73a246a5cc3c13"];
          description = "Tile UUIDs to leave out, by the id Tile gives them.";
        };
      };

      config = lib.mkIf cfg.enable {
        cosmos.system.impermanence.persist.directories = [
          {
            directory = stateDir;
            inherit user;
            group = user;
            mode = "0750";
          }
        ];

        # Read by systemd as root and handed to the unit as a credential, so
        # it needs no owner of its own.
        sops.secrets."keys/tile/password" = {};

        users.users.${user} = {
          isSystemUser = true;
          group = user;
          home = stateDir;
        };
        users.groups.${user} = {};

        systemd.services.tile-traccar = {
          description = "Forward Tile tracker locations to Traccar";
          wantedBy = ["multi-user.target"];
          after = ["network-online.target" "traccar.service"];
          wants = ["network-online.target"];

          environment = {
            TILE_EMAIL = cfg.email;
            TRACCAR_ENDPOINT = "http://127.0.0.1:${toString traccar.protocolPorts.osmand}";
            POLL_INTERVAL = toString cfg.interval;
            DISCOVERY_INTERVAL = toString cfg.discoveryInterval;
            IGNORED_TILES = builtins.toJSON cfg.ignoredTiles;
            MAX_AGE = toString cfg.maxAge;
            CLIENT_UUID_FILE = "${stateDir}/client-uuid";
            PYTHONUNBUFFERED = "1";
          };

          serviceConfig = {
            User = user;
            Group = user;
            LoadCredential = "tile-password:${config.sops.secrets."keys/tile/password".path}";
            ExecStart = "${python}/bin/python ${script}";

            # Tile's API goes down, the network flaps, a poll raises: none of
            # that should end the feed. Bad credentials exit 1 and still come
            # back every 30s, which is loud in the journal but harmless.
            Restart = "always";
            RestartSec = 30;

            # DynamicUser is deliberately off: it pairs with StateDirectory to
            # relocate state under /var/lib/private, which cannot work once
            # impermanence has bind-mounted the directory (the same EBUSY that
            # broke crowdsec's registration).
            StateDirectory = baseNameOf stateDir;
            WorkingDirectory = stateDir;

            CapabilityBoundingSet = [""];
            LockPersonality = true;
            MemoryDenyWriteExecute = true;
            NoNewPrivileges = true;
            PrivateDevices = true;
            PrivateTmp = true;
            PrivateUsers = true;
            ProtectClock = true;
            ProtectControlGroups = true;
            ProtectHome = true;
            ProtectHostname = true;
            ProtectKernelLogs = true;
            ProtectKernelModules = true;
            ProtectKernelTunables = true;
            ProtectProc = "invisible";
            ProtectSystem = "strict";
            RestrictAddressFamilies = ["AF_INET" "AF_INET6"];
            RestrictNamespaces = true;
            RestrictRealtime = true;
            RestrictSUIDSGID = true;
            SystemCallArchitectures = "native";
            SystemCallFilter = ["@system-service" "~@privileged" "~@resources"];
          };
        };
      };
    };
  };
}
