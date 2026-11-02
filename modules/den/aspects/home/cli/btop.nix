# home.btop
{...}: {
  den.aspects.home.btop.homeManager = {...}: {
    programs.btop = {
      enable = true;
      settings = {
        hide_userland_threads = 1;
        highlight_base_name = 1;
        show_cpu_temperature = 1;
        show_program_path = 0;
      };
    };

    # stylix's theme file is switched by home.theme; SIGUSR2 rereads it.
    cosmos.desktops.common.styling.modes.onSwitch = ''
      pkill -USR2 -x btop || true
    '';
  };
}
