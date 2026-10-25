# nvim rocq — Coqtail (needs the python3 provider).
{
  lib,
  config,
  pkgs,
  ...
}: let
  inherit (lib.modules) mkIf;

  cfg = config.cosmos.nvim.languages.rocq;
in {
  config = mkIf cfg.enable {
    withPython3 = true;

    extraPackages = with pkgs; [
      (python3.withPackages (ps:
        with ps; [
          pynvim
        ]))
    ];
    # If a symlink issue appears, patch plugin/coqtail.vim (not autoload/)
    # with --replace-fail so an upstream move breaks the build.
    extraPlugins = [pkgs.vimPlugins.Coqtail];
  };
}
