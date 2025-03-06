{config, ...}: {
  config = {
    console = {
      earlySetup = true; # Switch keymap for Nixos stage 1
      useXkbConfig = true; # use xkb.options in tty.
    };

    # Configure keymap in X11
    services.xserver.xkb.layout = "us";
    services.xserver.xkb.variant = "dvp";
    services.xserver.xkb.options = "caps:escape";
  };
}
