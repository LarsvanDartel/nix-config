{...}: {
  flake.modules.homeManager.claude = {pkgs, ...}: {
    home.packages = [pkgs.claude-code];

    cosmos.system.impermanence.persist = {
      files = [".claude.json"];
      directories = [".claude"];
    };
  };
}
