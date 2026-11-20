# _netbird-groups — kanidm-provision fragment for one `netbird-*` group, merged into oauth2.netbird.
group: {
  # overwriteMembers off so hand-added members survive a redeploy.
  groups.${group} = {
    overwriteMembers = false;
    members = ["lvdar"];
  };

  oauth2.netbird = {
    # Every netbird-* group needs these scopes, or a member of only this group is refused a token.
    scopeMaps.${group} = ["openid" "profile" "email"];

    # One-to-one on purpose: NetBird sets auto-groups to exactly this.
    claimMaps.groups.valuesByGroup.${group} = [group];
  };
}
