# home.oh-my-pi (https://omp.sh/)
{inputs, ...}: {
  flake-file.inputs.omp.url = "github:can1357/oh-my-pi";

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
