# roles.gaming — steam/gamemode/piper on top of the desktop. Gaming hosts
# include it.
{...}: {
  den.aspects.roles.gaming.nixos = {pkgs, ...}: {
    services.ratbagd.enable = true;

    environment.systemPackages = with pkgs; [piper];

    programs.steam = {
      enable = true;
      extraCompatPackages = with pkgs; [proton-ge-bin];
    };

    programs.gamemode.enable = true;
  };
}
