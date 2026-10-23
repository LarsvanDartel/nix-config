# noctalia-qs — backport of quickshell's Qt 6.12 fix to noctalia's fork.
# Qt 6.12's moc requires complete meta types, which 0.0.12's forward-declared
# Hyprland/i3 IPC types are not. Warns once nixpkgs moves past 0.0.12; drop
# this if that release carries quickshell 5d5d49873fe8 (the patch will stop
# applying when it does).
{...}: {
  nixpkgs.overlays = [
    (final: prev: {
      noctalia-qs =
        prev.lib.warnIf (prev.noctalia-qs.version != "0.0.12") ''
          modules/pkgs/noctalia-qs.nix: nixpkgs' noctalia-qs is now ${prev.noctalia-qs.version}.
          Check whether it carries quickshell 5d5d49873fe8; delete the override or bump this guard.
        '' (prev.noctalia-qs.overrideAttrs (old: {
          patches =
            (old.patches or [])
            ++ [
              (final.fetchpatch {
                name = "quickshell-qt-6.12-moc-includes.patch";
                url = "https://github.com/quickshell-mirror/quickshell/commit/5d5d49873fe8cf1f99ddfd5006ceb2057c5c9b13.patch";
                # The fork's i3 accessors lack upstream's `const`, so those two
                # header hunks are carried rebased in ./_noctalia-qs instead.
                excludes = ["changelog/*" "src/x11/i3/ipc/monitor.hpp" "src/x11/i3/ipc/workspace.hpp"];
                hash = "sha256-twMRAPbAv9zU8ORjxXA1GO5MMMBO/kX75Pt+RgeIycA=";
              })
              ./_noctalia-qs/i3-qt-6.12.patch
            ];
        }));
    })
  ];
}
