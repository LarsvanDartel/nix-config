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
  den.aspects.services.coding-agents.nixos = {
    config,
    pkgs,
    ...
  }: let
    # AppArmor attaches by resolved path: a copy keeps root's and nixos' bash
    # out of agent-session. A symlink resolves to the shared bash; a wrapper
    # script loses the login -argv0.
    agentShell = pkgs.runCommand "agent-shell" {} ''
      install -Dm755 ${pkgs.bashInteractive}/bin/bash $out/bin/agent-shell
    '';
  in {
    # No wheel and no service groups: a prompt-injected agent gets this home
    # and nix builds, not the host's secrets or sudo.
    users.users.agent = {
      isNormalUser = true;
      description = "Coding agents";
      shell = "${agentShell}/bin/agent-shell";
      openssh.authorizedKeys.keys = authorizedKeys;
    };
    environment.shells = ["${agentShell}/bin/agent-shell"];

    # sshd-session's `@{shells_path} Ux` doesn't match the name agent-shell.
    security.apparmor.includes."local/sshd-session" = ''
      ${agentShell}/bin/agent-shell px -> agent-session,
    '';

    # Children inherit (ix); the deny rules hold even in complain mode.
    security.apparmor.policies.agent-session = {
      inherit (config.cosmos.security.apparmor) state;
      profile = ''
        abi <abi/5.0>,
        include <tunables/global>

        profile agent-session ${agentShell}/bin/agent-shell flags=(attach_disconnected,mediate_deleted) {
          include <abstractions/base-strict>
          include <abstractions/nameservice>
          include <abstractions/ssl_certs>

          network inet stream,
          network inet6 stream,
          network inet dgram,
          network inet6 dgram,
          network netlink raw,
          network unix stream,
          network unix dgram,

          /nix/store/** mrix,
          /run/current-system/** r,
          /etc/** r,

          owner /home/agent/ r,
          owner /home/agent/** rwlkmix,
          /tmp/ r,
          owner /tmp/** rwlkmix,
          /var/tmp/ r,
          owner /var/tmp/** rwlkmix,
          owner /run/user/*/ r,
          owner /run/user/*/** rwk,

          /nix/var/nix/daemon-socket/socket rw,
          /nix/var/nix/profiles/per-user/agent/** rwl,
          /nix/var/nix/gcroots/per-user/agent/** rwl,

          /dev/ptmx rw,
          /dev/pts/* rw,
          /dev/tty rw,

          @{PROC}/ r,
          @{PROC}/{loadavg,meminfo,stat,uptime,cpuinfo,version,mounts} r,
          @{PROC}/sys/** r,
          @{PROC}/@{pids}/{stat,status,cmdline,comm} r,
          owner @{PROC}/@{pids}/** rw,
          @{sys}/devices/system/cpu/** r,
          @{sys}/fs/cgroup/user.slice/** r,

          /run/wrappers/wrappers.*/utempter ix,
          /run/utmp rwk,

          ptrace (read, trace) peer=agent-session,
          signal (send, receive) peer=agent-session,

          deny /run/wrappers/wrappers.*/{su,sudo,sudoedit,sg,newgrp,mount,umount,newuidmap,newgidmap,unix_chkpwd,fusermount,fusermount3,pkexec} x,
          deny userns,
          deny mount,
          deny umount,
          deny pivot_root,
          deny capability,
          deny ptrace (trace) peer=unconfined,
          deny /etc/ssh/ssh_host_* rwlkmx,
          deny /etc/shadow rwlk,
          deny /home/agent/.config/systemd/** wl,
          deny /home/agent/.local/share/systemd/** wl,
          deny /home/agent/.config/environment.d/** wl,
          deny /run/user/*/bus rw,
          deny /run/user/*/systemd/** rw,
          deny /run/dbus/system_bus_socket rw,
          deny /run/secrets{,.d}/** rwlkmx,
          deny /run/secrets-for-users{,.d}/** rwlkmx,
          deny /run/credentials/** rwlkmx,
          deny /run/keys/** rwlkmx,
          deny /persist/** rwlkmx,
          deny /run/{docker.sock,podman/**,libpod/**,containers/**,phpfpm/**,postgresql/**,kanidmd/**,minecraft/**,nginx/**} rwlkmx,
          deny /var/lib/** rwlkmx,
          deny /tank/** rwlkmx,
          deny /home/nixos/** rwlkmx,
          deny /root/** rwlkmx,

          include if exists <local/agent-session>
        }
      '';
    };

    # Mesh only. mosh-server binds the first free port from 60001, so this
    # caps it at ten concurrent sessions.
    programs.mosh = {
      enable = true;
      openFirewall = false;
    };
    cosmos.services.netbird.client.exposedUdpPorts = lib.range 60001 60010;

    # A mosh-server whose client vanished (Termux killed, phone off) never
    # exits on its own and keeps its port; ten of those lock mosh out.
    # tmux keeps the agent running regardless.
    services.openssh.extraConfig = ''
      Match User agent
        SetEnv MOSH_SERVER_NETWORK_TMOUT=86400
    '';

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
