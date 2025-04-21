{
  orca-slicer = {
    networking.firewall = {
      extraCommands = ''
        iptables -A nixos-fw -p udp --source 192.168.2.0/24 --dport 2021:2021 -j nixos-fw-accept
      '';
      extraStopCommands = ''
        iptables -D nixos-fw -p udp --source 190.168.2.0/24 --dport 2021:2021 -j nixos-fw-accept || true
      '';
    };
  };
}
