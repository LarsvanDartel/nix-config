# services.coding-agents — an unprivileged, sandboxed `agent` user running omp in tmux, reached over ssh or mosh.
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
  # See docs/src/networking.md#coding-agents-on-endeavour.
  den.aspects.services.coding-agents.nixos = {
    config,
    pkgs,
    ...
  }: let
    # AppArmor attaches by resolved path: a copy keeps other users' bash out of agent-session.
    # A symlink resolves to the shared bash; a wrapper script loses the login -argv0.
    agentShell = pkgs.runCommand "agent-shell" {} ''
      install -Dm755 ${pkgs.bashInteractive}/bin/bash $out/bin/agent-shell
    '';

    # Same reason as agentShell: a private store path that agent-session can
    # px into agent-sandbox without catching anyone else's landrun.
    sandboxRunner = pkgs.runCommand "omp-landrun" {} ''
      install -Dm755 ${pkgs.landrun}/bin/landrun $out/bin/omp-landrun
    '';

    devPorts = "20000:20999";

    ompPkg = inputs.omp.packages.${pkgs.stdenv.hostPlatform.system}.default;

    ompWrapper = pkgs.writeShellApplication {
      name = "omp";
      runtimeInputs = [pkgs.coreutils pkgs.gnugrep];
      text = ''
        if [[ -n ''${OMP_SANDBOX_REPO:-} ]]; then
          exec ${ompPkg}/bin/omp "$@"
        fi

        dev=$(realpath -e "$HOME/dev")
        here=$(realpath -e .)
        if [[ $here/ != "$dev"/?*/ ]]; then
          echo "omp: start omp inside a clone in ~/dev/<repo> (omp-unsandboxed skips the sandbox)" >&2
          exit 1
        fi

        rel=''${here#"$dev"/}
        name=''${rel%%/*}
        # landrun splits flag values on commas.
        if [[ $name == .* || $name == *,* ]]; then
          echo "omp: unsupported repo directory name: $name" >&2
          exit 1
        fi
        root=$dev/$name

        if ! grep -qw landlock /sys/kernel/security/lsm; then
          echo "omp: kernel has no Landlock; refusing to start" >&2
          exit 1
        fi

        home=$HOME/.cache/omp-sandbox/$name
        mkdir -p "$home/tmp" "$home/run"
        chmod 700 "$home/run"
        for link in .omp .config; do
          if [[ -e $home/$link && ! -L $home/$link ]]; then rm -rf "''${home:?}/$link"; fi
          ln -sfn "$HOME/$link" "$home/$link"
        done

        # endeavour's kernel has Landlock ABI v7; landrun asks for v9 (unix-socket rules) unless best-effort.
        args=(--best-effort --log-level error --ignore-missing --unrestricted-network
          --rox /nix/store --rox /run/current-system --rox /etc
          --ro /proc --ro /sys --ro "$HOME/.config"
          --rw /dev
          --rwx "$root" --rwx "$home" --rwx "$HOME/.omp" --rwx /tmp --rwx /var/tmp)

        unset XDG_CACHE_HOME XDG_DATA_HOME XDG_STATE_HOME XDG_CONFIG_HOME DBUS_SESSION_BUS_ADDRESS SSH_AUTH_SOCK
        export OMP_SANDBOX_REPO=$root XDG_RUNTIME_DIR=$home/run TMPDIR=$home/tmp
        export HOME=$home
        # landrun passes only the variables named here; compgen is missing from non-interactive bash.
        while IFS= read -r -d "" kv; do args+=(--env "''${kv%%=*}"); done < <(env -0)

        exec ${sandboxRunner}/bin/omp-landrun "''${args[@]}" -- ${ompPkg}/bin/omp "$@"
      '';
    };

    sandboxedOmp = pkgs.symlinkJoin {
      name = "omp-sandboxed";
      paths = [
        ompWrapper
        (pkgs.runCommand "omp-unsandboxed" {} "mkdir -p $out/bin; ln -s ${ompPkg}/bin/omp $out/bin/omp-unsandboxed")
      ];
    };

    sharedRules = ''
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
          ${sharedRules}
          @{sys}/kernel/security/lsm r,

          ptrace (read, trace) peer=agent-session,
          signal (send, receive) peer=agent-session,
          ptrace (read) peer=agent-sandbox,
          signal (send) peer=agent-sandbox,

          ${sandboxRunner}/bin/omp-landrun px -> agent-sandbox,

          include if exists <local/agent-session>
        }
      '';
    };

    # Reached only from agent-session's px on omp-landrun.
    security.apparmor.policies.agent-sandbox = {
      inherit (config.cosmos.security.apparmor) state;
      profile = ''
        abi <abi/5.0>,
        include <tunables/global>

        profile agent-sandbox flags=(attach_disconnected,mediate_deleted) {
          ${sharedRules}
          ptrace (read, trace) peer=agent-sandbox,
          ptrace (readby) peer=agent-session,
          signal (send, receive) peer=agent-sandbox,
          signal (receive) peer=agent-session,

          # Landlock ABI v7 can't stop connect() on path sockets; this keeps a sandboxed omp from driving the tmux server outside the sandbox.
          # Plain deny: enforced and silent even in complain mode; `audit deny` is downgraded to allow+log there.
          deny /tmp/tmux-*/** rw,
          deny /run/user/*/tmux-*/** rw,

          include if exists <local/agent-sandbox>
        }
      '';
    };

    # ESTABLISHED first: sshd-session and mosh-server run as agent and must answer the mesh.
    networking.firewall = {
      # Loopback 32768-60999 stays open for omp's eval bridge (binds 127.0.0.1:0), so a service on a
      # random port there stays reachable; fixed service ports do not.
      extraCommands = ''
        ip46tables -N agent-egress 2>/dev/null || true
        ip46tables -F agent-egress
        ip46tables -D OUTPUT -m owner --uid-owner agent -j agent-egress 2>/dev/null || true
        ip46tables -A OUTPUT -m owner --uid-owner agent -j agent-egress
        ip46tables -A agent-egress -m conntrack --ctstate ESTABLISHED,RELATED -j RETURN
        ip46tables -A agent-egress -m addrtype --dst-type LOCAL -p udp --dport 53 -j RETURN
        ip46tables -A agent-egress -m addrtype --dst-type LOCAL -p tcp --dport 53 -j RETURN
        iptables -w -A agent-egress -d 127.0.0.1 -p tcp -m multiport --dports ${devPorts},32768:60999 -j RETURN
        ip6tables -w -A agent-egress -d ::1 -p tcp -m multiport --dports ${devPorts},32768:60999 -j RETURN
        ip46tables -A agent-egress -m addrtype --dst-type LOCAL -j REJECT
        iptables -w -A agent-egress -d 0.0.0.0/8,10.0.0.0/8,100.64.0.0/10,169.254.0.0/16,172.16.0.0/12,192.168.0.0/16,224.0.0.0/4 -j REJECT
        ip6tables -w -A agent-egress -d fc00::/7,fe80::/10,ff00::/8 -j REJECT
      '';
      extraStopCommands = ''
        ip46tables -D OUTPUT -m owner --uid-owner agent -j agent-egress 2>/dev/null || true
        ip46tables -F agent-egress 2>/dev/null || true
        ip46tables -X agent-egress 2>/dev/null || true
      '';
    };

    # Mesh only. mosh-server binds the first free port from 60001, so this
    # caps it at ten concurrent sessions.
    programs.mosh = {
      enable = true;
      openFirewall = false;
    };
    cosmos.services.netbird.client.exposedUdpPorts = lib.range 60001 60010;

    # A mosh-server whose client vanished never exits and keeps its port; ten of those lock mosh out.
    services.openssh.extraConfig = ''
      Match User agent
        SetEnv MOSH_SERVER_NETWORK_TMOUT=86400
    '';

    home-manager.users.agent = {
      imports = [
        den.aspects.home.core.homeManager
        den.aspects.home.oh-my-pi.homeManager
      ];

      programs.omp.package = sandboxedOmp;

      home.file.".omp/agent/AGENTS.md".text = ''
        - You run in a sandbox: you can write only this repository, `$HOME` (a per-repository scratch home), `~/.omp`, `/tmp` and `/var/tmp`; other repositories and the real home are unreadable. A permission error on another path is the sandbox, not a bug: don't retry it with chmod, sudo or another path.
        - Network: the public internet works. This host's services, the LAN and the fleet mesh are blocked.
        - Local servers you start must listen on 127.0.0.1 or ::1, port 20000–20999.
        - You have no push, ssh or deploy credentials. Leave commits for the user to pull.
      '';

      # Not home.git: its SSH signing and git@github.com rewrites need keys agent lacks.
      programs.git = {
        enable = true;
        settings.user = {
          name = "agent@endeavour";
          email = "agent@endeavour.nb.lvdar.nl";
        };
      };

      home.packages = [inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.tmux];

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
