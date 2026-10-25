# nvim plugins — small always-on plugins; the rest of this dir is imported here.
{lib, ...}: {
  imports =
    map (n: ./. + "/${n}")
    (builtins.attrNames (lib.filterAttrs (n: t: t == "regular" && n != "default.nix" && lib.hasSuffix ".nix" n) (builtins.readDir ./.)));

  plugins = {
    lz-n.enable = true;

    csvview.enable = true;
  };
}
