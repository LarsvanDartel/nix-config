# apparmor-d — roddhjav/apparmor.d prebuilt for NixOS: store-path @{bin}/@{lib} and exec-rule priorities so store globs don't conflict.
{...}: {
  nixpkgs.overlays = [
    (final: _prev: {
      apparmor-d = final.callPackage (
        {
          lib,
          buildGoModule,
          fetchFromGitHub,
        }:
          buildGoModule {
            pname = "apparmor-d";
            version = "0-unstable-2026-11-15";

            src = fetchFromGitHub {
              owner = "roddhjav";
              repo = "apparmor.d";
              rev = "5c34009a6ea104831c9a91a578f9255dbb289fe2";
              hash = "sha256-4lsINgPantxkHRxFDkAMrvM78+rMArdQOgFkJTa/ObA=";
            };

            vendorHash = "sha256-aGqnmqCnp3uhbO93P2iFU5BEQMZAFnWfnwpGUM9pF/0=";
            subPackages = ["cmd/prebuild"];

            postPatch = ''
              substituteInPlace apparmor.d/tunables/multiarch.d/system \
                --replace-fail '@{bin}=/{,usr/}bin' '@{bin}=/{nix/store/*/,}{,usr/}bin' \
                --replace-fail '@{sbin}=/{,usr/}{,s}bin  #aa:only pacman' '@{sbin}=/{nix/store/*/,}{,usr/}{,s}bin  #aa:only pacman' \
                --replace-fail '@{lib}=/{,usr/}lib{,exec,32,64}' '@{lib}=/{nix/store/*/,}{,usr/}lib{,exec,32,64}'
              substituteInPlace pkg/aa/apparmor.go \
                --replace-fail '"bin", Values: []string{"/{,usr/}bin"}' '"bin", Values: []string{"/{nix/store/*/,}{,usr/}bin"}' \
                --replace-fail '"lib", Values: []string{"/{,usr/}lib{,exec,32,64}"}' '"lib", Values: []string{"/{nix/store/*/,}{,usr/}lib{,exec,32,64}"}'
              substituteInPlace pkg/builder/userspace.go \
                --replace-fail '"sbin", Values: []string{"/{,usr/}{,s}bin"}' '"sbin", Values: []string{"/{nix/store/*/,}{,usr/}{,s}bin"}'
            '';

            postInstall = ''
              # arch: merged /usr and @{sbin}=bin, NixOS's closest layout; nixos is not an upstream distribution.
              DISTRIBUTION=arch $out/bin/prebuild --abi 5 --version 5.0 --buildir build
              cd build/apparmor.d
              # Store globs make FHS "exact beats glob" exec rules conflict; priorities restore that order.
              skip='^\s*(priority|deny|audit deny|profile|include|signal|ptrace|unix|dbus|network|capability|mount|umount|remount|pivot_root|change_profile|abi|alias|userns|io_uring|mqueue|all)\b'
              broad='^(\s*)((owner|audit)\s+)?(\S*/\*\*?)(\s+)([a-zA-Z]*x(\s*->\s*\S+)?,)'
              exact='^(\s*)((owner|audit)\s+)?([^ \t*?[#]+)(\s+)([a-zA-Z]*x(\s*->\s*\S+)?,)'
              find . -type f -exec sed -E -i \
                -e "/$skip/! s#$broad#\1priority=-1 \2\4\5\6#" \
                -e "/$skip/! s#$exact#\1priority=1 \2\4\5\6#" {} +
              # Units hand profiles systemd-owned fds; without attach_disconnected those fail EACCES even in complain mode.
              att='attach_disconnected'
              find . -type f -exec sed -E -i \
                -e "/^\s*profile\s.*flags=\(/{/attach_disconnected|unconfined/! s#flags=\(#flags=($att,#;}" \
                -e "/^\s*profile\s/{/flags=/! s#\s*\{\s*\$# flags=($att) {#;}" {} +
              mkdir -p $out/etc/apparmor.d
              cp -r abstractions tunables mappings $out/etc/apparmor.d/
              find groups profiles-* -type f -exec cp -t $out/etc/apparmor.d/ {} +
              rm -r $out/bin
            '';

            meta = {
              description = "apparmor.d profiles prebuilt for NixOS store paths";
              homepage = "https://github.com/roddhjav/apparmor.d";
              license = lib.licenses.gpl2Only;
              platforms = lib.platforms.linux;
            };
          }
      ) {};
    })
  ];
}
