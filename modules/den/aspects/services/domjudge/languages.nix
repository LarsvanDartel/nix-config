# services.domjudge.languages — the judge's languages beyond the image's.
#
# The judgehost image's chroot has gcc, OpenJDK 21 and pypy3 3.9. The other
# toolchains are copied, with their closure, into one tree mounted at the
# chroot's /nix (so submissions see it and not the host store), and
# _files/judgehost-start.sh adds that mount to every judging's chroot.
# Compile scripts in _files/executables call them by store path; the
# domjudge-languages job uploads any that differ from the DB's and enables
# exactly the languages below.
{den, ...}: {
  den.aspects.services.domjudge.languages = {
    includes = [den.aspects.services.domjudge];

    nixos = {
      config,
      lib,
      pkgs,
      ...
    }: let
      python = pkgs.python3;
      go = pkgs.go;
      node = pkgs.nodejs-slim;
      # Official distributions where nixpkgs' build drags in a toolchain the
      # chroot already has: pkgs.kotlin wraps a 600 MiB OpenJDK and pkgs.rustc
      # a 1.6 GiB LLVM + cc closure. These run on the chroot's java and cc.
      kotlinc = pkgs.runCommand "kotlinc-${pkgs.kotlin.version}" {nativeBuildInputs = [pkgs.unzip];} ''
        unzip -q ${pkgs.kotlin.src}
        mv kotlinc $out
      '';
      # Pinned: bump the version and both hashes together
      # (nix store prefetch-file <url>).
      rustVersion = "1.99.0";
      rustComponent = name: hash:
        pkgs.fetchurl {
          url = "https://static.rust-lang.org/dist/${name}-${rustVersion}-x86_64-unknown-linux-gnu.tar.xz";
          inherit hash;
        };
      rust = pkgs.runCommand "rust-${rustVersion}" {} ''
        tar -xJf ${rustComponent "rustc" "sha256-dxcboqA0X98qvE/t2lXW3geNrnpoUnwovox33MlgS9U="}
        tar -xJf ${rustComponent "rust-std" "sha256-Pljf8tC3IZa16k6QU24XTUAN6IVkpSaUaGuB4JEWmTM="}
        mkdir $out
        cp -r rustc-*/rustc/. rust-std-*/rust-std-x86_64-unknown-linux-gnu/. $out/
      '';
      chrootStore = pkgs.runCommand "domjudge-chroot-store" {} ''
        mkdir -p $out/store
        cp -a --reflink=auto $(<${pkgs.closureInfo {rootPaths = [python kotlinc rust go node];}}/store-paths) $out/store/
      '';

      mkExecutable = name: substitutions:
        pkgs.runCommand "domjudge-executable-${name}.zip" {nativeBuildInputs = [pkgs.zip];} ''
          cp -r ${./_files/executables + "/${name}"} src
          chmod -R u+w src
          substituteInPlace src/run ${substitutions}
          cd src
          find . -exec touch -h -d @315532800 {} +
          find . -type f | sort | zip -q -X -@ $out
        '';
      executables = {
        py3 = mkExecutable "py3" "--replace-fail @python3@ ${python}/bin/python3";
        kt = mkExecutable "kt" "--replace-fail @kotlinc@ ${kotlinc}";
        rs = mkExecutable "rs" "--replace-fail @rust@ ${rust}";
        go = mkExecutable "go" "--replace-fail @go@ ${go}";
        js = mkExecutable "js" "--replace-fail @node@ ${node}/bin/node";
      };

      # Exactly these languages are enabled: POST /languages disables the rest.
      languagesJson = pkgs.writeText "domjudge-languages.json" (builtins.toJSON [
        {id = "c";}
        {id = "cpp";}
        {id = "java";}
        {
          id = "kotlin";
          name = "Kotlin ${lib.versions.majorMinor pkgs.kotlin.version}";
          # kt/run detects the main class, as Java's script does.
          entry_point_required = false;
          compiler.version_command = "${kotlinc}/bin/kotlinc -version";
          runner.version_command = "${kotlinc}/bin/kotlin -version";
        }
        {
          id = "python3";
          name = "Python ${lib.versions.majorMinor python.version}";
          extensions = ["py" "py3"];
          compiler.version_command = "${python}/bin/python3 --version";
          runner.version_command = "${python}/bin/python3 --version";
        }
        {
          id = "rust";
          name = "Rust ${lib.versions.majorMinor rustVersion}";
          compiler.version_command = "${rust}/bin/rustc --version";
        }
        {
          id = "go";
          name = "Go ${lib.versions.majorMinor go.version}";
          extensions = ["go"];
          compiler.version_command = "${go}/bin/go version";
        }
        {
          id = "javascript";
          name = "JavaScript (Node.js ${lib.versions.major node.version})";
          runner.version_command = "${node}/bin/node --version";
        }
      ]);
    in {
      virtualisation.oci-containers.containers.domjudge-judgehost = {
        cmd = ["/scripts/judgehost-start.sh"];
        volumes = [
          "${./_files/judgehost-start.sh}:/scripts/judgehost-start.sh:ro"
          "${chrootStore}:/chroot/domjudge/nix:ro"
        ];
      };

      systemd.services.domjudge-languages = (import ./_lib.nix).mkApiJob {inherit config lib pkgs;} {
        name = "domjudge-languages";
        description = "Configure DOMjudge's languages and compile scripts";
        runtimeInputs = with pkgs; [findutils jq unzip];
        # DOMjudge has no Go language, and POST /languages skips unknown ones.
        rootSql = ''
          INSERT IGNORE INTO executable (execid, description, type) VALUES ('go', 'go', 'compile');
          INSERT IGNORE INTO language (langid, externalid, name, extensions, allow_submit, compile_script)
            VALUES ('go', 'go', 'Go', '["go"]', 0, 'go');
        '';
        text = ''
          # What DOMjudge judges with: file contents and executable bits.
          digest() {
            local d
            d=$(mktemp -d -p "$CACHE_DIRECTORY")
            unzip -q "$1" -d "$d" 2>/dev/null || true
            (cd "$d" && find . -type f -print0 | sort -z | xargs -0 sha256sum && find . -type f -perm -u+x | sort)
            rm -rf "$d"
          }
          for e in ${lib.concatStringsSep " " (lib.mapAttrsToList (id: zip: "${id}=${zip}") executables)}; do
            id=''${e%%=*} zip=''${e#*=}
            # A new language's executable has no files yet.
            if ! dj "$api/executables/$id" | jq -r . | base64 -d >"$CACHE_DIRECTORY/current.zip"; then
              : >"$CACHE_DIRECTORY/current.zip"
            fi
            if [ "$(digest "$zip")" != "$(digest "$CACHE_DIRECTORY/current.zip")" ]; then
              echo "updating executable $id"
              dj -F "executable=@$zip;type=application/zip" "$api/languages/$id/executable"
            fi
          done
          dj -F "json=@${languagesJson};type=application/json" "$api/languages" >/dev/null
        '';
      };
    };
  };
}
