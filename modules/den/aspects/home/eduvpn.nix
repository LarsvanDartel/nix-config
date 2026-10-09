# home.eduvpn — impermanence persist dir for the eduVPN client (state.json holds
# OAuth tokens; unpersisted, every boot re-runs the browser login).
{...}: {
  den.aspects.home.eduvpn.homeManager = {...}: {
    cosmos.system.impermanence.persist.directories = [".config/eduvpn"];
  };
}
