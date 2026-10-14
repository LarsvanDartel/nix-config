# _netbird-groups — the kanidm-provision fragment for one `netbird-*` group.
#
# A plain function to `import` (underscored, so import-tree skips it). Each
# group is a kanidm group AND a `groups` claim value NetBird matches against
# distribution lists. Fragments merge into services/netbird.nix's
# oauth2.netbird client: scopeMaps and valuesByGroup are attrsOf.
group: {
  # overwriteMembers off so hand-added members survive a redeploy.
  groups.${group} = {
    overwriteMembers = false;
    members = ["lvdar"];
  };

  oauth2.netbird = {
    # Every netbird-* group, not just netbird-users: otherwise a member of
    # only one service group is refused a token with a misleading scopes
    # error. Services' distribution lists still decide access.
    scopeMaps.${group} = ["openid" "profile" "email"];

    # One-to-one on purpose: NetBird sets auto-groups to exactly this.
    claimMaps.groups.valuesByGroup.${group} = [group];
  };
}
