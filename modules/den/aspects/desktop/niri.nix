# desktop.niri — the niri scrollable-tiling compositor, as a WRAPPED package:
# the whole config is baked into the derivation by nix-wrapper-modules' niri
# wrapper (typed settings → KDL, `niri validate` at build time), so no
# config.kdl is written to $HOME, and the wrapper patches the session's
# niri.service to the wrapped binary. The body lives in ./_niri/system.nix
# because voyager's `specialisation.niri` needs the same content
# (specialisation bodies cannot `include` a den aspect). Deliberately does NOT
# include desktop.xdg-portal: that installs the hyprland portal, whereas
# `programs.niri` brings its own gnome + gtk portals.
{
  den,
  inputs,
  ...
}: {
  den.aspects.desktop.niri = {
    # keyd supplies the tap-vs-hold Mod key the binds below use; niri has no way
    # to bind a modifier on its own.
    includes = with den.aspects.desktop; [greetd keyd];
    nixos = import ./_niri/system.nix {inherit inputs;};
  };
}
