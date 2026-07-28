# services.containers — podman (docker-compat). Uses the extraGroups collector.
{...}: {
  den.aspects.services.containers.nixos = {...}: {
    cosmos.user.extraGroups = ["podman" "kvm"];
    boot.kernelModules = ["kvm-intel"];
    virtualisation = {
      containers.enable = true;
      podman = {
        enable = true;
        dockerCompat = true;
        defaultNetwork.settings.dns_enabled = true;
      };
    };
  };
}
