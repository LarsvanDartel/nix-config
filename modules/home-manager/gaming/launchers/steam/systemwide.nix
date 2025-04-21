{
  steam = {
    modules.unfree.allowedPackages = [
      "steam"
      "steam-original"
      "steam-unwrapped"
      "steam-run"
    ];

    programs.steam.enable = true;
  };
}
