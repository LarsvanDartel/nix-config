# home.eduvpn — impermanence persist dir for the eduVPN client (program and
# routing are nixos-level via services.eduvpn). state.json holds the server
# list + OAuth tokens; unpersisted, every boot re-runs the browser login.
{...}: {
  den.aspects.home.eduvpn.homeManager = {...}: {
    cosmos.system.impermanence.persist.directories = [".config/eduvpn"];
  };
}
