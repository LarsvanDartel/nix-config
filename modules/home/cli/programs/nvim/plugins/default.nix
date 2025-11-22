{lib, ...}: {
  imports = lib.cosmos.get-non-default-nix-files ./.;

  config = {
    programs.nixvim = {
      plugins = {
        # Lazy loading
        lz-n.enable = true;

        gitsigns = {
          enable = true;
          settings.signs = {
            add.text = "+";
            change.text = "~";
          };
        };

        csvview.enable = true;
      };
    };
  };
}
