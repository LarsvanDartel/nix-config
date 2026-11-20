# home.btop — btop system monitor
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

    cosmos.desktops.common.styling.modes.onSwitch = ''
      pkill -USR2 -x btop || true
    '';
  };
}
