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
