{...}: {
  flake.modules.nixos.docker = {...}: {
    cosmos.system.impermanence.persist.directories = ["/var/lib/docker"];

    virtualisation.docker = {
      enable = true;
    };

    cosmos.user.extraGroups = ["docker"];
  };
}
