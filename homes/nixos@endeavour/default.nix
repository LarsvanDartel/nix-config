{
  cosmos = {
    profiles.common.enable = true;

    system.impermanence = {
      persist = {
        directories = [
          "dev"
        ];
      };
    };
  };

  home.stateVersion = "24.11";
}
