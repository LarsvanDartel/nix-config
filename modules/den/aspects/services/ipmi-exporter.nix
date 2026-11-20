# services.ipmi-exporter — BMC sensors (temperatures, fans, PSU power), in-band.
{den, ...}: let
  # A plain binding, not an option: the scrape-target entry must be static (see
  # services/prometheus.nix). Hand-allocated: 9500 node-exporter, 9501 spindle, 9091-9304 opencloud.
  port = 9502;
in {
  den.aspects.services.ipmi-exporter = {
    includes = [den.aspects.services.netbird.client];

    scrape-target = {host, ...}: {
      job = "ipmi";
      instance = host.name;
      inherit port;
    };

    nixos = {lib, ...}: {
      services.prometheus.exporters.ipmi = {
        enable = true;
        inherit port;
      };

      # freeipmi's in-band driver insists on root and needs /dev/ipmi0, both
      # of which the exporter framework's sandbox removes.
      systemd.services.prometheus-ipmi-exporter.serviceConfig = {
        DynamicUser = lib.mkForce false;
        User = lib.mkForce "root";
        Group = lib.mkForce "root";
        PrivateDevices = lib.mkForce false;
        DeviceAllow = ["/dev/ipmi0 rw"];
      };

      cosmos.services.netbird.client.exposedPorts = [port];
    };
  };
}
