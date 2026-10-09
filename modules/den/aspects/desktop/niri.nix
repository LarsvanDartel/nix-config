# desktop.niri — the niri compositor as a WRAPPED package (config baked in by
# nix-wrapper-modules). Body in ./_niri/system.nix, shared with voyager's
# specialisation. Deliberately does NOT include desktop.xdg-portal (hyprland
# portal); `programs.niri` brings its own.
{
  den,
  inputs,
  ...
}: {
  den.aspects.desktop.niri = {
    includes = with den.aspects.desktop; [greetd keyd];
    nixos = import ./_niri/system.nix {inherit inputs;};
  };
}
