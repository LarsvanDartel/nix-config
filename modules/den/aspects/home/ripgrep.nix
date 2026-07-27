# home.ripgrep
{...}: {
  den.aspects.home.ripgrep.homeManager = {...}: {
    programs.ripgrep = {
      enable = true;
      arguments = [
        "--colors=line:style:bold"
        "--hidden"
        "--line-number"
        "--no-heading"
        "--color=always"
        "--smart-case"
        "--glob=!*.{jpg,jpeg,png,gif,svg}"
      ];
    };
  };
}
