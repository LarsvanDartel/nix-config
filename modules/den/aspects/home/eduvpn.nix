# home.eduvpn — impermanence persist dir for the eduVPN client (the program is
# installed, and the routing it needs configured, at the nixos level via
# services.eduvpn).
#
# state.json is the whole of the client's memory: the discovery cache, the
# servers you have added and the OAuth tokens for them. Without this every boot
# starts at "add a server" and re-runs the browser login.
{...}: {
  den.aspects.home.eduvpn.homeManager = {...}: {
    cosmos.system.impermanence.persist.directories = [".config/eduvpn"];
  };
}
