# The niri home config, as a plain home-manager module *factory*.
#
# Imported by BOTH `den.aspects.home.niri` (see ../../home/desktop/niri.nix) and
# voyager's `specialisation.niri` — specialisation bodies are ordinary NixOS
# modules and cannot `include` a den aspect, so the shared content lives here.
# Call it as `import ./_niri/home.nix {}`.
{}: {
  lib,
  osConfig,
  pkgs,
  ...
}: let
  niri = osConfig.programs.niri.package;

  # nix-wrapper-modules renders every KDL node name and property key quoted:
  #
  #   "binds"  {
  #     "F19"  { "spawn-sh" "noctalia-shell ipc call controlCenter toggle" }
  #   }
  #
  # niri reads that happily — it is legal KDL — but the hand-rolled text parsers
  # that read a niri config do not. noctalia's keybind-cheatsheet gives up at
  # `line.startsWith("binds")`, never enters the binds block, finds nothing and
  # never finishes loading.
  #
  # Unquoting the leading token of each line and the property keys yields the
  # conventional spelling. Running `niri validate` on the result is what makes
  # this safe rather than a hopeful regex: if the transform ever mangled the
  # config, the build fails instead of publishing something that lies about what
  # niri is running.
  readableConfig = pkgs.runCommand "niri-config.kdl" {} ''
    sed -E \
      -e 's/^([[:space:]]*)"([^"]+)"/\1\2/' \
      -e 's/"([A-Za-z0-9_-]+)"=/\1=/g' \
      ${niri}/niri-config.kdl > $out
    ${lib.getExe niri} validate --config $out
  '';
in {
  home.packages = with pkgs; [
    playerctl
    wl-clipboard
  ];

  cosmos.system.impermanence.persist.directories = ["Pictures/screenshots"];

  # The wrapped niri is handed its config through NIRI_CONFIG, pointing into the
  # store, so ~/.config/niri/config.kdl is never consulted and normally does not
  # exist at all. Plenty of tooling assumes the conventional path anyway, so
  # publish it there — regenerated every rebuild, and validated to be the same
  # config niri actually booted with.
  xdg.configFile."niri/config.kdl".source = readableConfig;
}
