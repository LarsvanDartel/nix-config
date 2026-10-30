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

    # cups-filters ≥1.25.12 prefers Apple Raster (image/urf) over PWG Raster
    # whenever a driverless printer advertises both, but the TS5100's URF
    # duplex path prints the front side, turns the sheet, then ends the job
    # (OpenPrinting/cups-filters#660, same bug on other Canon models). The
    # printer's own IPP attributes advertise full PWG Raster support, so
    # force the generated PPD onto that filter once lpadmin has (re)created
    # it.
    systemd.services.ts5100-pwg-raster-ppd =
      lib.mkIf
      (lib.warnIf (pkgs.cups-filters.version != "2.0.1") ''
          modules/den/aspects/desktop/printing.nix: nixpkgs' cups-filters moved
          off 2.0.1, the version this URF-duplex workaround was written
          against. Reprint a multi-page duplex job; if the back sides print,
          delete this service and the comment above it.
        ''
        true)
      {
        description = "Force the ts5100 queue onto PWG Raster instead of URF";
        after = ["ensure-printers.service"];
        requires = ["ensure-printers.service"];
        wantedBy = ["multi-user.target"];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${pkgs.gnused}/bin/sed -i 's#image/urf image/urf#image/pwg-raster image/pwg-raster#' /etc/cups/ppd/ts5100.ppd";
          ExecStartPost = "${pkgs.systemd}/bin/systemctl try-restart cups.service";
        };
      };
  };
}
