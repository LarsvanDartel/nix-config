{...}: {
  flake.modules.homeManager.thunderbird = {...}: {
    programs.thunderbird = {
      enable = true;
      # home-manager requires at least one profile with isDefault set. Accounts
      # are added in the UI rather than declared here: for Proton, enable the
      # proton-mail-bridge feature and point an account at 127.0.0.1:1143 (IMAP)
      # / 127.0.0.1:1025 (SMTP) using the bridge-generated password.
      profiles.default.isDefault = true;
    };

    cosmos.system.impermanence.persist.directories = [".thunderbird"];
  };
}
