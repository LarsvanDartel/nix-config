# home.oh-my-pi (https://omp.sh/)
{inputs, ...}: {
  flake-file.inputs.omp.url = "github:can1357/oh-my-pi";

  den.aspects.home.oh-my-pi.homeManager = {
    pkgs,
    lib,
    ...
  }: let
    system = pkgs.stdenv.hostPlatform.system;

    # oh-my-pi@97f945c1 (2026-09-20) added axe-core as a bun dependency but
    # never regenerated nix/bun.nix (bun2nix's vendored fetchurl table), so
    # the upstream package's bunNodeModulesInstallPhase falls through to a
    # live registry.npmjs.org fetch for just that one package — which the
    # sandboxed Nix builder has no network for, and every voyager build
    # fails on `home-manager-lvdar.service` as a result. Patch the missing
    # entry in locally (same fetchBunDeps machinery package.nix itself uses,
    # borrowed via inputs.omp.inputs.bun2nix so the version matches exactly)
    # until upstream reruns bun2nix. Safe to drop once
    # https://github.com/can1357/oh-my-pi/blob/master/nix/bun.nix carries
    # axe-core again.
    ompBun2Nix = inputs.omp.inputs.bun2nix.packages.${system}.bun2nix;
    rootPackageJson = lib.importJSON (inputs.omp + "/package.json");
    patchedDependencies =
      lib.mapAttrs (_: patch: inputs.omp + "/${patch}")
      rootPackageJson.patchedDependencies;
    patchOverrides = ompBun2Nix.patchedDependenciesToOverrides {inherit patchedDependencies;};
  in {
    imports = [inputs.omp.homeManagerModules.default];

    programs.omp = {
      enable = true;

      package = inputs.omp.packages.${system}.default.overrideAttrs (old: {
        bunDeps = ompBun2Nix.fetchBunDeps {
          bunNix = {
            fetchurl,
            copyPathToStore,
            fetchFromGitHub,
            fetchgit,
          }:
            (import (inputs.omp + "/nix/bun.nix") {
              inherit fetchurl copyPathToStore fetchFromGitHub fetchgit;
            })
            // {
              "axe-core@4.13.0" = fetchurl {
                url = "https://registry.npmjs.org/axe-core/-/axe-core-4.13.0.tgz";
                hash = "sha512-UzGt8zg7Ny8djbYMhxl2zuEevVa7r2gJjYY5Lwr1xM7+XU2nd6CkIWFTVcCIbAP63vSz71NaVyyuSk9lHKcy0A==";
              };
            };
          overrides = patchOverrides;
        };
      });

      # The full config, verbatim from ~/.omp/agent/config.yml. Declaring it
      # matters: home-manager-<user>.service re-runs on every boot and the
      # upstream module's activation `install`s this yaml over
      # ~/.omp/agent/config.yml — a partial declaration would revert
      # everything undeclared (that is how theme etc. got wiped by a reboot
      # while the persisted `.omp` kept login/sessions intact). Consequence:
      # `/settings` or `omp config set` changes only live until the next
      # boot; make them HERE instead.
      settings = {
        startup.quiet = true;
        modelRoles.default = "opencode-go/glm-5.2";
        symbolPreset = "nerd";
        composer.shape = "field";
        theme = {
          dark = "titanium";
          light = "light";
        };
        # OMP's own onboarding marker — carried over so a fresh install
        # does not replay the setup wizard.
        setupVersion = 2;
      };
    };

    cosmos.system.impermanence.persist = {
      directories = [".omp"];
    };
  };
}
