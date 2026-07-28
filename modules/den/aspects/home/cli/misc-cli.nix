# home.misc-cli — small package-only CLI tools from the home baseline (xh,
# dnslookup) that don't warrant their own aspect.
{...}: {
  den.aspects.home.misc-cli.homeManager = {pkgs, ...}: {
    home.packages = with pkgs; [
      xh
      dnslookup
    ];
  };
}
