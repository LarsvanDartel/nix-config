# desktop.niri — the niri compositor as a wrapped package; its home half goes to every user.
{
  den,
  inputs,
  cosmosStyling,
  ...
}: {
  den.aspects.desktop.niri = {
    includes = with den.aspects.desktop; [greetd keyd];
    provides.to-users.includes = [den.aspects.home.niri];
    nixos = import ./_niri/system.nix {inherit inputs cosmosStyling;};
  };
}
