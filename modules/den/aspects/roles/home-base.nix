# roles.home-base — the home baseline every user gets, via
# den.schema.user.includes (defaults.nix).
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
