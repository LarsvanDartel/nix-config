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
