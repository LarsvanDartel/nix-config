# home.remmina — remote desktop client (SPICE/VNC/RDP); reaches services.genix-vm.
{...}: {
  den.aspects.home.remmina.homeManager = {pkgs, ...}: {
    cosmos.system.impermanence.persist.directories = [
      ".local/share/remmina"
      ".config/remmina"
    ];
    home.packages = with pkgs; [remmina];
  };
}
