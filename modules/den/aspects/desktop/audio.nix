# desktop.audio — pipewire stack.
{...}: {
  den.aspects.desktop.audio.nixos = {pkgs, ...}: {
    services.pulseaudio.enable = false;
    security.rtkit.enable = true;
    services.pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
      wireplumber.enable = true;
      # The module exits the whole daemon when Xwayland's display goes away, killing all outputs.
      extraConfig.pipewire."10-no-x11-bell"."context.properties"."module.x11.bell" = false;
    };
    programs.noisetorch.enable = true;

    environment.systemPackages = with pkgs; [pulsemixer];
  };
}
