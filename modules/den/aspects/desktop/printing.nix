# desktop.printing — cups with a driverless IPP queue for the home LAN
# printer (Canon TS5100, AirPrint/IPP Everywhere; pinned by IP because the
# printer's mDNS name does not resolve without the nss module, see below).
{...}: {
  den.aspects.desktop.printing.nixos = {
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
  };
}
