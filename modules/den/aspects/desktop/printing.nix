# desktop.printing — cups with a driverless IPP queue for the home LAN
# printer (Canon TS5100, AirPrint/IPP Everywhere; pinned by IP because the
# printer's mDNS name does not resolve without the nss module, see below).
{...}: {
  den.aspects.desktop.printing.nixos = {
    pkgs,
    lib,
    ...
  }: let
    # The PPD cups generated from the printer's IPP attributes (`-m
    # everywhere`), vendored so registering the queue never needs the printer:
    # `-m everywhere` queries it on every cups start, and while it was off that
    # failed cups-post-start and Restart=on-failure looped cups every ~3.5s
    # (2649 restarts on 2026-11-12).
    #
    # Edited from what the printer asks for: it reports
    # `document-format-preferred: image/urf` although it also supports PWG
    # Raster, and its URF duplex path prints the front side, turns the sheet,
    # then ends the job (same bug class as OpenPrinting/cups-filters#660 and
    # #490 on other Canon models). The `image/urf` cupsFilter2 line is
    # therefore `image/pwg-raster`. Registered as a static model, cupsd loads
    # exactly this file, so no post-start patching is needed.
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
      drivers = [ts5100Ppd];
    };

    hardware.printers = {
      ensureDefaultPrinter = "ts5100";
      ensurePrinters = [
        {
          name = "ts5100";
          description = "Canon TS5100 series";
          deviceUri = "ipp://192.168.2.84/ipp/print";
          model = "ts5100.ppd";
        }
      ];
    };
  };
}
