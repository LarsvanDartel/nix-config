# hardware.fingerprint — fprintd reader service.
{...}: {
  den.aspects.hardware.fingerprint.nixos = {...}: {
    cosmos.system.impermanence.persist.directories = ["/var/lib/fprint"];
    systemd.services.fprintd = {
      wantedBy = ["multi-user.target"];
      serviceConfig.Type = "simple";
    };
    services.fprintd.enable = true;
  };
}
