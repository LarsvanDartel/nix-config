# home.oh-my-pi (https://omp.sh/)
{inputs, ...}: {
  flake-file.inputs.omp.url = "github:can1357/oh-my-pi";

  den.aspects.home.oh-my-pi.homeManager = {...}: {
    imports = [inputs.omp.homeManagerModules.default];

    programs.omp = {
      enable = true;

      # The full config, verbatim from ~/.omp/agent/config.yml. Declaring it
      # matters: home-manager-<user>.service re-runs on every boot and the
      # upstream module's activation `install`s this yaml over
      # ~/.omp/agent/config.yml — a partial declaration would revert
      # everything undeclared (that is how theme etc. got wiped by a reboot
      # while the persisted `.omp` kept login/sessions intact). Consequence:
      # `/settings` or `omp config set` changes only live until the next
      # boot; make them HERE instead.
      settings = {
        startup.quiet = true;
        modelRoles.default = "opencode-go/glm-5.2";
        symbolPreset = "nerd";
        composer.shape = "field";
        theme = {
          dark = "titanium";
          light = "light";
        };
        # OMP's own onboarding marker — carried over so a fresh install
        # does not replay the setup wizard.
        setupVersion = 2;
      };
    };

    cosmos.system.impermanence.persist = {
      directories = [".omp"];
    };
  };
}
