{lib, ...}: {
  imports =
    map (n: ./. + "/${n}")
    (builtins.attrNames (lib.filterAttrs (n: t: t == "regular" && n != "default.nix" && lib.hasSuffix ".nix" n) (builtins.readDir ./.)));

  config = {
    programs.nixvim = {
      plugins = {
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
