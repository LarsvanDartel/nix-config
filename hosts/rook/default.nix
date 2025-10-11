{
  inputs,
  pkgs,
  ...
}: {
  imports = [
    # Hardware
    ./hardware-configuration.nix
    inputs.nixos-hardware.nixosModules.common-cpu-intel-cpu-only
    inputs.nixos-hardware.nixosModules.common-gpu-nvidia-nonprime

    # Disk layout
    inputs.disko.nixosModules.disko
    ./disko.nix
  ];

  system = {
    impermanence = {
      enable = true;
      device = "/dev/disk/by-label/nixos";
    };
  };

  networking.hostId = "b8433556";

  profiles = {
    server.enable = true;
  };

  hardware = {
    nvidia = {
      modesetting.enable = true;
      powerManagement.enable = true;
      open = false;
      nvidiaPersistenced = true;
      videoAcceleration = true;
    };
    ipmi-fancontrol = {
      enable = true;
      dynamic = true;
      minSpeed = 5;
      nvidia-smi = {
        enable = true;
        maxTemp = 105;
      };
    };
  };

  sops.secrets."keys/zfs/tank" = {};
  systemd.services."zfs-decode-key" = {
    description = "Decode ZFS raw key from SOPS secret";
    after = ["sops-nix.service"];
    before = ["zfs-load-key.service" "zfs-import.target"];
    wantedBy = ["zfs-import.target"];
    serviceConfig = {
      Type = "oneshot";
      StandardOutput = "journal";
      StandardError = "journal";
    };
    script = ''
      install -m 0700 -d /run/keys
      base64 -d /run/secrets/keys/zfs/tank > /run/keys/zfs-tank.key
      chmod 0400 /run/keys/zfs-tank.key
    '';
  };

  system.stateVersion = "24.11";
}
