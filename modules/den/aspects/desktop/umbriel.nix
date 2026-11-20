# desktop.umbriel — the Umbriel compositor as a second greeter session; its home half goes to every user.
{den, ...}: {
  den.aspects.desktop.umbriel = {
    includes = with den.aspects.desktop; [greetd keyd];
    provides.to-users.includes = [den.aspects.home.umbriel];
    nixos = import ./_umbriel/system.nix {};
  };
}
