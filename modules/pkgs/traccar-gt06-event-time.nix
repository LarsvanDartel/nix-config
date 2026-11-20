# traccar — patch: gt06 modular event blocks use their own big-endian time as device time, and Jimi event 0x13 maps to tampering.
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
