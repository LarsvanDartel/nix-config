# MCSR (Minecraft speedrunning) toolchain — a nested `pkgs.mcsr.*` namespace.
{...}: {
  nixpkgs.overlays = [
    (final: _prev: {
      mcsr = {
        floating = final.callPackage (
          {
            stdenvNoCC,
            fetchFromGitHub,
          }:
            stdenvNoCC.mkDerivation {
              pname = "floating";
              version = "0-unstable-2025-08-26";

              src = fetchFromGitHub {
                owner = "Esensats";
                repo = "waywall-floating";
                rev = "c18d2f5c8d4b4261b69d2a7b8cf8f3edacc1ee67";
                hash = "sha256-Cpco+U+rfo1HRvPs+KI1SfYTyImXrkzcKZ0IGiDZJvA=";
              };

              dontBuild = true;
              dontCheck = true;

              installPhase = ''
                runHook preInstall

                mkdir -p $out/floating
                cp *.lua $out/floating

                runHook postInstall
              '';
            }
        ) {};

        graalvm-21 = final.callPackage (
          {
            lib,
            stdenv,
            fetchurl,
            graalvmPackages,
            useMusl ? false,
          }: let
            hashes = {
              "x86_64-linux" = {
                url = "https://download.oracle.com/graalvm/21/archive/graalvm-jdk-21.0.9_linux-x64_bin.tar.gz";
                hash = "sha256-cLTSX7sxHZiLhsm2HleAKouWfbYW7mFyMMMYEnbkH3E=";
              };
              "aarch64-linux" = {
                url = "https://download.oracle.com/graalvm/21/archive/graalvm-jdk-21.0.9_linux-aarch64_bin.tar.gz";
                hash = "sha256-Xp1Il0tCaV3LQ4yHIF+Kig1cWyyX11LTaaswG0xc9+0=";
              };
            };
          in
            graalvmPackages.buildGraalvm {
              pname = "graalvm-oracle";
              version = "21.0.9";

              src = fetchurl hashes.${stdenv.hostPlatform.system};

              inherit useMusl;

              meta.platforms = lib.platforms.linux;
            }
        ) {};

        modcheck = final.callPackage (
          {
            lib,
            stdenvNoCC,
            fetchurl,
            makeWrapper,
            temurin-bin-25,
            java ? temurin-bin-25,
          }:
            stdenvNoCC.mkDerivation (finalAttrs: {
              pname = "modcheck";
              version = "3.1.1";

              src = fetchurl {
                url = "https://github.com/tildejustin/modcheck/releases/download/${finalAttrs.version}/modcheck-${finalAttrs.version}.jar";
                hash = "sha256-qAMZmoW74ExQls47GE2biiibTvHyKsOpXOJWu41q10k=";
              };

              nativeBuildInputs = [makeWrapper];

              dontUnpack = true;

              installPhase = ''
                runHook preInstall

                install -Dm644 $src $out/share/modcheck/modcheck.jar

                makeWrapper ${lib.getExe java} $out/bin/modcheck \
                    --add-flags "-jar $out/share/modcheck/modcheck.jar"

                runHook postInstall
              '';

              meta = {
                description = "Minecraft SpeedRun Mods Auto Installer/Updater";
                homepage = "https://github.com/tildejustin/modcheck";
                platforms = lib.platforms.linux;
                mainProgram = "modcheck";
              };
            })
        ) {};

        ninjabrain-bot = final.callPackage (
          {
            lib,
            stdenvNoCC,
            fetchurl,
            libx11,
            libxinerama,
            libxkbcommon,
            libxt,
            makeWrapper,
            temurin-bin-17,
            java ? temurin-bin-17,
            extraJavaArgs ? ["-Dawt.useSystemAAFontSettings=on"],
          }:
            stdenvNoCC.mkDerivation (finalAttrs: {
              pname = "ninjabrain-bot";
              version = "1.5.2";

              src = fetchurl {
                url = "https://github.com/Ninjabrain1/Ninjabrain-Bot/releases/download/${finalAttrs.version}/Ninjabrain-Bot-${finalAttrs.version}.jar";
                hash = "sha256-mAmfYyGpDUrOwTQA6G0F96+NYOVjnC84Qn6WjccUUP8=";
              };

              nativeBuildInputs = [makeWrapper];

              dontUnpack = true;

              installPhase = ''
                runHook preInstall

                install -Dm644 $src $out/share/ninjabrain-bot/ninjabrain-bot.jar

                makeWrapper ${lib.getExe java} $out/bin/ninjabrain-bot \
                    --add-flags "${lib.escapeShellArgs extraJavaArgs} -jar $out/share/ninjabrain-bot/ninjabrain-bot.jar" \
                    --prefix LD_LIBRARY_PATH : ${
                  lib.makeLibraryPath [
                    libx11
                    libxinerama
                    libxkbcommon
                    libxt
                  ]
                }

                runHook postInstall
              '';

              meta = {
                description = "Stronghold calculator for Minecraft speedrunning";
                homepage = "https://github.com/Ninjabrain1/Ninjabrain-Bot";
                license = lib.licenses.gpl3;
                platforms = lib.platforms.linux;
                mainProgram = "ninjabrain-bot";
              };
            })
        ) {};

        waywork = final.callPackage (
          {
            stdenvNoCC,
            fetchFromGitHub,
          }:
            stdenvNoCC.mkDerivation {
              pname = "waywork";
              version = "0-unstable-2025-11-29";

              src = fetchFromGitHub {
                owner = "Esensats";
                repo = "waywork";
                rev = "60ab89dfe32d894845a759a08cebd3d710262bcb";
                hash = "sha256-XF+FgnLRnn0MydVN3Qthg/CwC8p5+8jo0QhlpPpaWMc=";
              };

              dontBuild = true;
              dontCheck = true;

              installPhase = ''
                runHook preInstall

                mkdir -p $out/waywork
                cp *.lua $out/waywork

                runHook postInstall
              '';
            }
        ) {};
      };
    })
  ];

  perSystem = {pkgs, ...}: {
    packages = {
      mcsr-floating = pkgs.mcsr.floating;
      mcsr-graalvm-21 = pkgs.mcsr.graalvm-21;
      mcsr-modcheck = pkgs.mcsr.modcheck;
      mcsr-ninjabrain-bot = pkgs.mcsr.ninjabrain-bot;
      mcsr-waywork = pkgs.mcsr.waywork;
    };
  };
}
