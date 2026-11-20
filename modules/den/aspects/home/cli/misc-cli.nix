# home.misc-cli — small package-only CLI tools (xh, dnslookup)
{...}: {
  den.aspects.home.misc-cli.homeManager = {pkgs, ...}: {
    home.packages = with pkgs; [
      xh
      dnslookup
    ];
  };
}
