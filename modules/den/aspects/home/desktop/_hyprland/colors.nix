{config, ...}: {
  wayland.windowManager.hyprland.settings = with config.lib.stylix.colors.withHashtag; {
    background = {_var = base00;};
    surface = {_var = base00;};
    surface_dim = {_var = base00;};
    surface_container_lowest = {_var = base00;};

    surface_container_low = {_var = base01;};
    surface_container = {_var = base01;};

    surface_container_high = {_var = base02;};
    surface_container_highest = {_var = base02;};
    surface_variant = {_var = base02;};

    surface_bright = {_var = base03;};

    on_background = {_var = base05;};
    on_surface = {_var = base05;};

    on_surface_variant = {_var = base04;};

    inverse_surface = {_var = base06;};
    inverse_on_surface = {_var = base01;};

    primary = {_var = base0D;};
    primary_fixed = {_var = base0D;};
    primary_fixed_dim = {_var = base0D;};

    primary_container = {_var = base0C;};
    surface_tint = {_var = base0D;};

    on_primary = {_var = base00;};
    on_primary_container = {_var = base07;};
    on_primary_fixed = {_var = base00;};
    on_primary_fixed_variant = {_var = base01;};

    secondary = {_var = base0C;};
    secondary_fixed = {_var = base0C;};
    secondary_fixed_dim = {_var = base0C;};

    secondary_container = {_var = base03;};

    on_secondary = {_var = base00;};
    on_secondary_container = {_var = base07;};
    on_secondary_fixed = {_var = base00;};
    on_secondary_fixed_variant = {_var = base01;};

    tertiary = {_var = base0E;};
    tertiary_fixed = {_var = base0E;};
    tertiary_fixed_dim = {_var = base0E;};

    tertiary_container = {_var = base03;};

    on_tertiary = {_var = base00;};
    on_tertiary_container = {_var = base07;};
    on_tertiary_fixed = {_var = base00;};
    on_tertiary_fixed_variant = {_var = base01;};

    error = {_var = base08;};
    error_container = {_var = base08;};

    on_error = {_var = base00;};
    on_error_container = {_var = base07;};

    outline = {_var = base04;};
    outline_variant = {_var = base03;};

    inverse_primary = {_var = base0D;};

    shadow = {_var = base00;};
    scrim = {_var = base00;};
    source_color = {_var = base0D;};
  };
}
