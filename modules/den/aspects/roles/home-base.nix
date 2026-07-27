# roles.home-base — the home baseline every user gets (was the homeManager
# `common` aggregate). Included by the user aspects (lvdar, nixos).
{den, ...}: {
  den.aspects.roles.home-base.includes =
    (with den.aspects.home; [
      core
      zsh
      git
      ssh
      nvim
      bat
      btop
      direnv
      eza
      fd
      lazygit
      ripgrep
      yazi
      zoxide
      tmux
      misc-cli
    ])
    ++ [den.aspects.home."oh-my-posh"];
}
