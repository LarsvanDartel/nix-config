# desktop.umbriel — the Umbriel compositor as a second greeter session beside niri, body in ./_umbriel/system.nix; its home half (home.umbriel + noctalia) goes to every user via to-users.
{den, ...}: {
  den.aspects.desktop.umbriel = {
    includes = with den.aspects.desktop; [greetd keyd];
    provides.to-users.includes = [den.aspects.home.umbriel];
    nixos = import ./_umbriel/system.nix {};
  };
}
