# services.coding-agents — an unprivileged `agent` user that runs omp in tmux, reached as agent@endeavour over ssh or mosh (`mosh agent` from Termux); see docs/src/networking.md.
{
  cosmosLib,
  den,
  inputs,
  lib,
  ...
}: let
  keysDir = cosmosLib.get-flake-path "modules/den/aspects/core/_ssh-keys";
  authorizedKeys = map (f: builtins.readFile (keysDir + "/${f}")) (import (keysDir + "/authorized.nix"));
in {
  den.aspects.services.coding-agents.nixos = {pkgs, ...}: {
    # No wheel and no service groups: a prompt-injected agent gets this home
    # and nix builds, not the host's secrets or sudo.
    users.users.agent = {
      isNormalUser = true;
      description = "Coding agents";
      openssh.authorizedKeys.keys = authorizedKeys;
    };

    # Mesh only. mosh-server binds the first free port from 60001, so this
    # caps it at ten concurrent sessions.
    programs.mosh = {
      enable = true;
      openFirewall = false;
    };
    cosmos.services.netbird.client.exposedUdpPorts = lib.range 60001 60010;

    home-manager.users.agent = {
      imports = [
        den.aspects.home.core.homeManager
        den.aspects.home.oh-my-pi.homeManager
      ];

      home.packages = [
        pkgs.git
        inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.tmux
      ];

      cosmos.system.impermanence.persist.directories = ["dev"];

      # Every remote login lands in the one session, so a dropped phone
      # connection reattaches to the running agent instead of starting over.
      programs.bash = {
        enable = true;
        initExtra = ''
          if [[ $- == *i* && -z $TMUX && -n $SSH_CONNECTION ]]; then
            exec tmux new-session -A -s agent
          fi
        '';
      };
    };
  };
}
