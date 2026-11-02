# core.ntfy-options — the fleet's ntfy connection (cosmos.system.notifyFailure.{url,topic,user}), declared on every host so any aspect can push, laptops included; failure notifications themselves stay in roles.server.
{...}: {
  den.aspects.core.ntfy-options.nixos = {lib, ...}: let
    inherit (lib.options) mkOption;
    inherit (lib.types) str;
  in {
    options.cosmos.system.notifyFailure = {
      url = mkOption {
        type = str;
        default = "https://ntfy.lvdar.nl";
        description = ''
          The ntfy server. Public rather than the mesh address on purpose: the
          outages worth hearing about include "the mesh is down", and a sink
          only reachable over the mesh cannot report those.
        '';
      };

      topic = mkOption {
        type = str;
        default = "fleet";
        description = "ntfy topic every host publishes to.";
      };

      user = mkOption {
        type = str;
        default = "alerts";
        description = ''
          ntfy user to authenticate as. Its password is the shared secret
          `keys/ntfy/password`, and services/ntfy.nix provisions the account
          from the same value.
        '';
      };
    };
  };
}
