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
