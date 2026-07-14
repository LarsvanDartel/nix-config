{...}: {
  flake.modules.homeManager.common = {pkgs, ...}: {
    home.packages = with pkgs; [
      dnslookup
    ];
  };
}
