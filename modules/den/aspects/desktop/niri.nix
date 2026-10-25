# desktop.niri — the niri compositor as a WRAPPED package (config baked in by
# nix-wrapper-modules). Body in ./_niri/system.nix, shared with voyager's
# specialisation. Deliberately does NOT include desktop.xdg-portal (hyprland
# portal); `programs.niri` brings its own.
{
  den,
  inputs,
  ...
}: {
  flake-file.inputs.nix-wrapper-modules = {
    url = "github:nix-community/nix-wrapper-modules";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  den.aspects.desktop.niri = {
    includes = with den.aspects.desktop; [greetd keyd];
    nixos = import ./_niri/system.nix {inherit inputs;};
  };
}
