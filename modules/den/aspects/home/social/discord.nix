# home.discord
{...}: {
  den.aspects.home.discord.homeManager = {pkgs, ...}: {
    cosmos.system.impermanence.persist.directories = [".config/discord"];
    home.packages = with pkgs; [discord];
  };
}
