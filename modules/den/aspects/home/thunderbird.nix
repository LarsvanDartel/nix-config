# home.thunderbird
{...}: {
  den.aspects.home.thunderbird.homeManager = {...}: {
    programs.thunderbird = {
      enable = true;
      profiles.default.isDefault = true;
    };

    cosmos.system.impermanence.persist.directories = [".thunderbird"];
  };
}
