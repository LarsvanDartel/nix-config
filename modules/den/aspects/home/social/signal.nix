# home.signal
{...}: {
  den.aspects.home.signal.homeManager = {pkgs, ...}: {
    cosmos.system.impermanence.persist.directories = [".config/Signal"];
    home.packages = with pkgs; [signal-desktop];
  };
}
