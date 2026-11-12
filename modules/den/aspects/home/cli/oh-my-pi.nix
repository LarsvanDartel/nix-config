# home.oh-my-pi (https://omp.sh/)
{inputs, ...}: {
  # Pinned to a release tag so flake-bump cannot move it: every new rev is a
  # ~45 min uncached Rust+Bun build. Bump by hand when omp reports an update,
  # then `nix run .#write-flake` and `nix flake update omp`.
  flake-file.inputs.omp.url = "github:can1357/oh-my-pi/v18.19.0";

  den.aspects.home.oh-my-pi.homeManager = {...}: {
    imports = [inputs.omp.homeManagerModules.default];

    programs.omp = {
      enable = true;

      settings = {
        startup.quiet = true;
        modelRoles.default = "anthropic/claude-opus-5-5:high";
        symbolPreset = "nerd";
        composer.shape = "field";
        theme = {
          dark = "titanium";
          light = "light";
        };
        # Prevents a fresh install replaying the setup wizard.
        setupVersion = 2;
      };
    };

    cosmos.system.impermanence.persist = {
      directories = [".omp"];
    };
  };
}
