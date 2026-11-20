# desktop.printing — CUPS with a static driverless IPP queue for the home LAN Canon TS5100.
{...}: {
  den.aspects.desktop.printing.nixos = {
    pkgs,
    lib,
    ...
  }: let
    # Vendored: `-m everywhere` queries the printer on every cups start and loops cups while it is off.
    # cupsFilter2 is image/pwg-raster: URF duplex skips back sides (OpenPrinting/cups-filters#660).
    ts5100Ppd =
      lib.warnIf (pkgs.cups.version != "2.4.19") ''
        modules/den/aspects/desktop/printing.nix: nixpkgs' cups moved off 2.4.19,
        the version the PWG Raster preference in _printing/ts5100.ppd was
        written against. Swap that cupsFilter2 line back to image/urf and print
        a multi-page duplex job; if the back sides print, keep urf, else revert
        and bump this guard.
      '' (pkgs.runCommand "ts5100-ppd" {} ''
        install -Dm444 ${./_printing/ts5100.ppd} $out/share/cups/model/ts5100.ppd
      '');
  in {
    # .local names resolve via resolved's mDNS responder, also needed for netbird-gewis split DNS.
    # Not nssmdns4: it races resolved's responder, and avahi would only duplicate it.
    services.resolved.enable = true;
    services.resolved.settings.Resolve.MulticastDNS = true;

    # For discovery only (GUI print dialogs, `driverless` device lookups);
    # the queue itself is static, so cups-browsed stays off.
    services.avahi.enable = true;

    services.printing = {
      enable = true;
      browsed.enable = false;
      drivers = [ts5100Ppd];
    };

    hardware.printers = {
      ensureDefaultPrinter = "ts5100";
      ensurePrinters = [
        {
          name = "ts5100";
          description = "Canon TS5100 series";
          # Pinned by IP: the printer's mDNS name does not resolve without the nss module.
          deviceUri = "ipp://192.168.2.84/ipp/print";
          model = "ts5100.ppd";
        }
      ];
    };
  };
}
