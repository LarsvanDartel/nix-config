# Deployment-wide facts, applied to every host. Only options that exist on
# *every* host belong here — elsewhere it is an eval error.
{...}: {
  den.default.nixos = {
    cosmos.services.attic.client.serverUrl = "http://endeavour.nb.lvdar.nl:8090";
  };
}
