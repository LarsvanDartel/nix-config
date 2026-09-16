# update-blocklists — refresh the vendored oisd snapshots (vendored because
# oisd regenerates them continuously; services/unbound.nix has the
# reasoning):
#
#   nix run .#update-blocklists
#   git diff --stat modules/den/aspects/services/_unbound   # sanity check
#   git commit
#
# Commits nothing deliberately: a change to what the fleet's resolver blocks
# needs a human looking at it.
{...}: {
  nixpkgs.overlays = [
    (final: _prev: {
      update-blocklists = final.writeShellApplication {
        name = "update-blocklists";
        runtimeInputs = [final.curl final.coreutils final.git final.gnugrep];
        text = ''
          root=$(git rev-parse --show-toplevel)
          dir="$root/modules/den/aspects/services/_unbound"
          [ -d "$dir" ] || { echo "no $dir — run this inside the repo" >&2; exit 1; }

          fetch() {
            url=$1; dest=$2
            tmp=$(mktemp)
            echo "fetching $url"
            curl -fsSL --retry 3 -o "$tmp" "$url"

            # A truncated download or an error page would otherwise be
            # committed as a blocklist that silently blocks nothing. These
            # files are megabytes of local-zone lines; anything small is a
            # failure wearing a 200.
            size=$(stat -c %s "$tmp")
            if [ "$size" -lt 1000000 ]; then
              echo "refusing $url: only $size bytes, expected megabytes" >&2
              rm -f "$tmp"; exit 1
            fi
            if ! head -20 "$tmp" | grep -q "^# Title: oisd"; then
              echo "refusing $url: no oisd header, got something else" >&2
              rm -f "$tmp"; exit 1
            fi

            old=$(head -1 "$dest" 2>/dev/null || echo "# Version: none")
            new=$(head -1 "$tmp")
            mv "$tmp" "$dest"
            echo "  $(basename "$dest"): ''${old#\# Version: } -> ''${new#\# Version: }"
          }

          fetch https://big.oisd.nl/unbound  "$dir/oisd-big.unbound"
          fetch https://nsfw.oisd.nl/unbound "$dir/oisd-nsfw.unbound"

          echo
          echo "done. review with:  git diff --stat $dir"
        '';
      };
    })
  ];
}
