# home.claude (claude-code)
{...}: {
  den.aspects.home.claude.homeManager = {pkgs, ...}: {
    home.packages = [pkgs.claude-code];
    cosmos.system.impermanence.persist = {
      files = [".claude.json"];
      directories = [".claude"];
    };
  };
}
