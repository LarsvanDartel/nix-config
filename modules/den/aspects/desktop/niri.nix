# desktop.niri — the niri scrollable-tiling compositor, as a WRAPPED package.
#
# niri's whole config is baked into the derivation by `nix-wrapper-modules`' niri
# wrapper (typed settings → KDL, checked with `niri validate` at build time), so
# no config.kdl is written to $HOME. The wrapper also patches
# `share/systemd/user/niri.service` to the wrapped binary, so the session the
# greeter starts is the configured one.
#
# The body lives in ./_niri/system.nix because voyager's `specialisation.niri`
# has to apply the same content, and specialisation bodies are plain NixOS
# modules that cannot `include` a den aspect.
#
# Deliberately does NOT include desktop.xdg-portal: that aspect installs the
# hyprland portal, whereas `programs.niri` brings its own gnome + gtk portals.
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
