# desktop.niri — the niri compositor as a WRAPPED package (config baked in by nix-wrapper-modules), body in ./_niri/system.nix; its home half (home.niri + noctalia) goes to every user via to-users.
{
  den,
  inputs,
  ...
}: {
  den.aspects.desktop.niri = {
    includes = with den.aspects.desktop; [greetd keyd];
    provides.to-users.includes = [den.aspects.home.niri];
    nixos = import ./_niri/system.nix {inherit inputs;};
  };
}
