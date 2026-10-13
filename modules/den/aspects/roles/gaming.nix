# roles.gaming — steam/gamemode/piper on top of the desktop, plus home.steam for
# every user. Gaming hosts include it.
{den, ...}: {
  den.aspects.roles.gaming.provides.to-users.includes = [den.aspects.home.steam];

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
