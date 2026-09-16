# home.core — the home baseline plumbing: cosmos.user/impermanence option
# schema, nix settings, home-manager.enable, sops.
{inputs, ...}: {
  den.aspects.home.core.homeManager = {
    config,
    lib,
    ...
  }: let
    inherit (lib.options) mkOption;
    inherit (lib.types) str nullOr listOf coercedTo attrsOf bool;
  in {
    imports = [inputs.sops-nix.homeManagerModules.sops];

    options.cosmos = {
      user = {
        # den's define-user sets home.username/homeDirectory; mirror them for
        # the home features that read cosmos.user.
        name = mkOption {
          type = nullOr str;
          default = config.home.username;
        };
        home = mkOption {
          type = str;
          default = config.home.homeDirectory;
        };
      };

      security.sops.sopsFolder = mkOption {
        type = str;
        default = builtins.toString inputs.nix-secrets + "/users";
      };

      system.impermanence = {
        active = mkOption {
          type = bool;
          default = false;
          internal = true;
        };
        persist = {
          files = mkOption {
            type = listOf (coercedTo str (f: {file = f;}) (attrsOf str));
            default = [];
          };
          directories = mkOption {
            type = listOf (coercedTo str (d: {directory = d;}) (attrsOf str));
            default = [];
          };
        };
      };
    };

    config = {
      programs.home-manager.enable = true;

      nix.settings = {
        substituters = [
          "https://cache.nixos.org"
          "https://nix-community.cachix.org"
        ];
        trusted-public-keys = [
          "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
          "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        ];
        experimental-features = ["nix-command" "flakes"];
        warn-dirty = false;
        use-xdg-base-directories = true;
      };

      sops = {
        age.keyFile = "/home/${config.home.username}/.config/sops/age/keys.txt";
        defaultSopsFile = "${config.cosmos.security.sops.sopsFolder}/${config.home.username}.yaml";
        validateSopsFiles = false;
      };
    };
  };
}
