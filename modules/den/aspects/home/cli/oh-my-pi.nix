# home.oh-my-pi (https://omp.sh/)
{inputs, ...}: {
  flake-file.inputs.omp.url = "github:can1357/oh-my-pi";

  den.aspects.home.oh-my-pi.homeManager = {...}: {
    imports = [inputs.omp.homeManagerModules.default];

    programs.omp = {
      enable = true;
      settings.startup.quiet = true;
    };

    cosmos.system.impermanence.persist = {
      directories = [".omp"];
    };
  };
}
