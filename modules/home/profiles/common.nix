# Profile-level config for the home `common` aggregate. The baseline home
# features (zsh, nvim, git, ssh, bat, …) self-register into
# `flake.modules.homeManager.common` from their own files; this only sets the
# few cross-feature values.
{...}: {
  flake.modules.homeManager.common = {...}: {
    cosmos.cli.programs.git = {
      user = "LarsvanDartel";
      email = "larsvandartel73@gmail.com";
    };
    cosmos.cli.programs.yazi.defaultApplication = true;
  };
}
