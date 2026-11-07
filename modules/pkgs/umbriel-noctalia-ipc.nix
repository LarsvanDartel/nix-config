# umbriel: nixpkgs' 2026-10-16 snapshot predates the IPC noctalia 5.4.1 speaks
# (typed `action` requests, 2026-10-29; `minimized`/`minimizable` in window
# snapshots, 2026-10-24), so noctalia's taskbar actions fail and it warns on
# every window event, ~45k lines a day. Moved to the rev nixpkgs-unstable
# already ships, with its recipe's changes (libei, systemd, xwayland). Warns
# once nixpkgs moves umbriel off the old snapshot: then delete this.
{...}: {
  nixpkgs.overlays = [
    (final: prev: {
      umbriel =
        prev.lib.warnIf (prev.umbriel.version != "0-unstable-2026-10-16") ''
          modules/pkgs/umbriel-noctalia-ipc.nix: nixpkgs' umbriel is now ${prev.umbriel.version}.
          Delete this override if it is at least 0-unstable-2026-11-03.
        ''
        (prev.umbriel.overrideAttrs (old: {
          version = "0-unstable-2026-11-03";
          src = final.fetchFromGitHub {
            owner = "noctalia-dev";
            repo = "umbriel";
            rev = "e0da106317b10831e709618f52cc00bd7a9dc793";
            hash = "sha256-zQ+Kb+qj8s+HGAU/7h2pE9gnQKeZd7jiTN+3inaCY5w=";
          };
          buildInputs = old.buildInputs ++ [final.libei final.systemd];
          mesonInstallFlags = [];
          postInstall = ''
            if [ -f "$out/share/wayland-sessions/umbriel.desktop" ]; then
              substituteInPlace "$out/share/wayland-sessions/umbriel.desktop" \
                --replace-fail 'Exec=start-umbriel' "Exec=$out/bin/start-umbriel"
            fi
            wrapProgram $out/bin/umbriel \
              --prefix PATH : ${final.lib.makeBinPath [final.xwayland]}
          '';
        }));
    })
  ];
}
