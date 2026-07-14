# The `gaming` aggregate: extra bits on top of `desktop`. A gaming host imports
# `common`, `desktop` and `gaming`.
{...}: {
  flake.modules.nixos.gaming = {pkgs, ...}: {
    services.ratbagd.enable = true;

    environment.systemPackages = with pkgs; [
      piper
    ];

    # TODO: move to dedicated steam module
    programs.steam = {
      enable = true;
      extraCompatPackages = with pkgs; [
        proton-ge-bin
      ];
    };

    programs.gamemode.enable = true;
  };
}
