# php — PHP 8.5.12 ahead of nixpkgs: the 2026-10-21 out-of-band release for
# GHSA-w8hw-w9fx-j79w / GHSA-6wmf-4rv5-p3rp (PHP2Shell, pre-auth RCE, attacked
# before release). Firefly III and its data importer run on php85.
# Inert once nixpkgs reaches 8.5.12, so it cannot downgrade, and warns then.
{...}: {
  nixpkgs.overlays = [
    (final: prev: {
      php85 =
        if prev.lib.versionAtLeast prev.php85.version "8.5.12"
        then
          prev.lib.warn ''
            modules/pkgs/php.nix: nixpkgs' php85 is now ${prev.php85.version} (>= 8.5.12); delete the override.
          ''
          prev.php85
        else
          prev.php85.override {
            version = "8.5.12";
            # A tree, not the tarball: every extension builds from this source.
            # The three tests are new with the fix and run `php-cgi -n` on a
            # POST body; with -n the separately built filter extension is not
            # loaded, so they fail on "undefined function", not on the limit.
            # (packageOverrides would be the obvious hook, but php85 is a
            # withExtensions wrapper whose .override never reaches it.)
            phpSrc = final.applyPatches {
              name = "php-8.5.12-src";
              src = final.fetchurl {
                url = "https://www.php.net/distributions/php-8.5.12.tar.bz2";
                hash = "sha256-/7YO3EN87WO1E35JhNs3moERxQBJxxFRDYuVgnfvwag=";
              };
              postPatch = ''
                rm ext/filter/tests/oom_filter_default_encoded.phpt \
                  ext/filter/tests/oom_filter_input.phpt \
                  ext/filter/tests/oom_filter_input_array.phpt
              '';
            };
          };
    })
  ];
}
