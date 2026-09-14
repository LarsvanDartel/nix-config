# pkgs.python3Packages.tino — the `tino` Python package (github:confirm/tino),
# registered into python3Packages rather than built as a standalone
# application: it has no console-script entry point of its own — upstream
# runs it *as* a gunicorn worker target, "tino:create_app()" — so
# services/tino.nix composes the actual run environment with
# `python3.withPackages`.
#
# Upstream ships and supports only a Docker image, and calls a non-Docker
# install "not recommended and unsupported". That warning is about a manual
# Ubuntu-style install (chasing Python 3.14, the Typst CLI, and git-lfs by
# hand), not about anything Nix-specific: every runtime dependency already
# has a proper nixpkgs derivation, including the two Rust-backed ones
# (pycrdt, pycrdt-websocket), and nixpkgs' own `typst` package happens to
# already be pinned to exactly the 0.15.1 upstream's Dockerfile bundles. So
# packaging it natively costs nothing that "unsupported" actually protects
# against, and keeps it in the same shape as every other service here rather
# than being this fleet's first Docker container.
{...}: {
  nixpkgs.overlays = [
    (final: prev: {
      pythonPackagesExtensions =
        prev.pythonPackagesExtensions
        ++ [
          (pyFinal: _pyPrev: {
            tino = pyFinal.buildPythonPackage rec {
              pname = "tino";
              version = "1.20.1";
              pyproject = true;

              src = final.fetchFromGitHub {
                owner = "confirm";
                repo = "tino";
                tag = version;
                hash = "sha256-EnFlCeX0QGNfuTPKF8kveg1Z7ryAsqQbUoQv1BRZw1I=";
              };

              build-system = with pyFinal; [setuptools setuptools-scm wheel];

              # Upstream pins every dependency with `==`; nixpkgs carries
              # newer, compatible releases of all of them, and matching the
              # pin exactly would mean tracking tino's lockstep on every
              # nixpkgs bump for no correctness reason FastAPI/uvicorn/
              # gunicorn don't already give across minor versions.
              pythonRelaxDeps = true;

              dependencies = with pyFinal; [
                anyio
                authlib
                fastapi
                mcp
                gitpython
                gunicorn
                httpx
                itsdangerous
                pycrdt
                pycrdt-websocket
                python-multipart
                pyyaml
                uvicorn
              ];

              # setuptools_scm derives the version from git metadata, which
              # fetchFromGitHub does not provide.
              SETUPTOOLS_SCM_PRETEND_VERSION = version;

              # gitattributes ships at the repo root (routes bucket git repos
              # through git-lfs — see services/tino.nix), not inside the
              # `tino` package dir, so `tool.setuptools.package-data` never
              # installs it. Carried out as a share/ file instead of
              # duplicating its content in the NixOS module.
              postInstall = ''
                install -Dm444 tino/gitattributes $out/share/tino/gitattributes
              '';

              pythonImportsCheck = ["tino"];

              meta = {
                description = "Collaborative, self-hosted editing platform around Typst";
                homepage = "https://github.com/confirm/tino";
                license = final.lib.licenses.agpl3Only;
              };
            };
          })
        ];
    })
  ];
}
