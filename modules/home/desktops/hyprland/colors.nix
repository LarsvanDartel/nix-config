{config, ...}: {
  wayland.windowManager.hyprland.settings = with config.lib.stylix.colors.withHashtag; {
    "$background" = base00;
    "$surface" = base00;
    "$surface_dim" = base00;
    "$surface_container_lowest" = base00;

    "$surface_container_low" = base01;
    "$surface_container" = base01;

    "$surface_container_high" = base02;
    "$surface_container_highest" = base02;
    "$surface_variant" = base02;

    "$surface_bright" = base03;

    "$on_background" = base05;
    "$on_surface" = base05;

    "$on_surface_variant" = base04;

    "$inverse_surface" = base06;
    "$inverse_on_surface" = base01;

    "$primary" = base0D;
    "$primary_fixed" = base0D;
    "$primary_fixed_dim" = base0D;

    "$primary_container" = base0C;
    "$surface_tint" = base0D;

    "$on_primary" = base00;
    "$on_primary_container" = base07;
    "$on_primary_fixed" = base00;
    "$on_primary_fixed_variant" = base01;

    "$secondary" = base0C;
    "$secondary_fixed" = base0C;
    "$secondary_fixed_dim" = base0C;

    "$secondary_container" = base03;

    "$on_secondary" = base00;
    "$on_secondary_container" = base07;
    "$on_secondary_fixed" = base00;
    "$on_secondary_fixed_variant" = base01;

    "$tertiary" = base0E;
    "$tertiary_fixed" = base0E;
    "$tertiary_fixed_dim" = base0E;

    "$tertiary_container" = base03;

    "$on_tertiary" = base00;
    "$on_tertiary_container" = base07;
    "$on_tertiary_fixed" = base00;
    "$on_tertiary_fixed_variant" = base01;

    "$error" = base08;
    "$error_container" = base08;

    "$on_error" = base00;
    "$on_error_container" = base07;

    "$outline" = base04;
    "$outline_variant" = base03;

    "$inverse_primary" = base0D;

    "$shadow" = base00;
    "$scrim" = base00;
    "$source_color" = base0D;
  };
}
