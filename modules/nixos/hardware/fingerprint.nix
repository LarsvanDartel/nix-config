{...}: {
  flake.modules.nixos.fingerprint = {...}: {
    cosmos.system.impermanence.persist.directories = ["/var/lib/fprint"];

    # Enable the fingerprint reader service
    systemd.services.fprintd = {
      wantedBy = ["multi-user.target"];
      serviceConfig.Type = "simple";
    };

    # Enable the fprintd service
    services.fprintd.enable = true;
  };
}
