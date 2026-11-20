# apparmor-match

Source: `modules/den/aspects/core/_apparmor/match.py`.

## Regenerating the profile lists

`core/_apparmor/common.nix` and `hosts/_apparmor/<host>.nix` list the apparmor.d profiles to load. Regenerate them from the profiles' attachment paths and what each host has installed or running:

```bash
d=$(nix build --no-link --print-out-paths .#nixosConfigurations.endeavour.pkgs.apparmor-d)/etc/apparmor.d
for h in endeavour gaia; do ssh $h 'bash -s' < modules/den/aspects/core/_apparmor/collect.sh > /tmp/$h.tsv; done
python3 modules/den/aspects/core/_apparmor/match.py $d /tmp/{endeavour,gaia}.tsv
```

The output has one block per host. Names matched on every given host belong in `common.nix`, the rest in that host's file. `core/apparmor.nix`'s `excluded` filters the result again.
