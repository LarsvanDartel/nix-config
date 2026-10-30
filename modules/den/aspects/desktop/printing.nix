# desktop.printing — cups with a driverless IPP queue for the home LAN
# printer (Canon TS5100, AirPrint/IPP Everywhere; pinned by IP because the
# printer's mDNS name does not resolve without the nss module, see below).
{...}: {
  den.aspects.desktop.printing.nixos = {
    pkgs,
    lib,
    ...
  }: {
    # .local names resolve through resolved's mDNS responder, which is already
    # on for netbird-gewis's split DNS. Not nssmdns4: it races resolved's
    # responder, and avahi would only duplicate that responder.
    services.resolved.enable = true;
    services.resolved.settings.Resolve.MulticastDNS = true;

    # For discovery only (GUI print dialogs, `driverless` device lookups);
    # the queue itself is static, so cups-browsed stays off.
    services.avahi.enable = true;

    services.printing = {
      enable = true;
      browsed.enable = false;
    };

    hardware.printers = {
      ensureDefaultPrinter = "ts5100";
      ensurePrinters = [
        {
          name = "ts5100";
          description = "Canon TS5100 series";
          deviceUri = "ipp://192.168.2.84/ipp/print";
          # IPP Everywhere: the printer reports its capabilities (AirPrint 1.7,
          # URF), so no vendor driver or PPD is needed.
          model = "everywhere";
        }
      ];
    };

    # The TS5100 reports `document-format-preferred: image/urf` over IPP
    # (confirmed with `ipptool get-printer-attributes`), even though it also
    # fully supports PWG Raster (`document-format-supported` lists both).
    # cupsd honours that preference and bakes it into the printer's *live*
    # MIME filter graph the moment `lpadmin -m everywhere` registers the
    # queue — editing the PPD file afterwards doesn't touch that cached
    # routing, only the file on disk. And the TS5100's URF duplex path
    # prints the front side, turns the sheet, then ends the job there
    # (same bug class as OpenPrinting/cups-filters#660 and #490 on other
    # Canon models). So: patch the generated PPD onto PWG Raster, then
    # re-register that exact file with `-P` (not `-m`, which would
    # re-query the printer and put urf straight back) to make cupsd
    # re-read it into the live graph. hardware.printers' own provisioning
    # runs as cups.service's postStart now (not a separate unit), so this
    # has to append there too.
    systemd.services.cups.postStart = lib.mkIf (lib.warnIf (pkgs.cups.version != "2.4.19") ''
        modules/den/aspects/desktop/printing.nix: nixpkgs' cups moved off
        2.4.19, the version this URF-duplex workaround was written against.
        Reprint a multi-page duplex job; if the back sides print, delete
        this postStart append and the comment above it.
      ''
      true) (lib.mkAfter ''
      ppd=/etc/cups/ppd/ts5100.ppd
      ${pkgs.gnused}/bin/sed -i 's#image/urf image/urf#image/pwg-raster image/pwg-raster#' "$ppd"
      lpadmin -p ts5100 -P "$ppd"
    '');
  };
}
