# traccar: gt06 modular (0x70) event blocks carry their own big-endian
# timestamp, which 6.17.0 reads little-endian and discards. Alarms then take
# the last GNSS fix's time, and a stationary Jimi asset tracker (GNSS off)
# reports removal with a fix older than notificator.timeThreshold, so the
# push is skipped as an "old event". The patch uses the event time as device
# time and maps event 0x13 (Jimi "tamper alert") to tampering.
{...}: {
  nixpkgs.overlays = [
    (_final: prev: {
      traccar =
        prev.lib.warnIf (prev.traccar.version != "6.17.0") ''
          modules/pkgs/traccar-gt06-event-time.nix: nixpkgs' traccar is now ${prev.traccar.version}.
          Check whether Gt06ProtocolDecoder's MSG_GPS_MODULAR 0x34 block still discards the event time; drop the patch or bump this guard.
        ''
        (prev.traccar.overrideAttrs (old: {
          patches = (old.patches or []) ++ [./_traccar/gt06-modular-event-time.patch];
        }));
    })
  ];
}
