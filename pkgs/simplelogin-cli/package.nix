{
  lib,
  stdenvNoCC,
  nodejs,
  pnpm_9,
  fetchPnpmDeps,
  pnpmConfigHook,
  fetchFromGitHub,
  makeWrapper,
}:
stdenvNoCC.mkDerivation rec {
  pname = "simplelogin-cli";
  version = "0.2.2";

  src = fetchFromGitHub {
    owner = "KennethWussmann";
    repo = "simplelogin-cli";
    tag = "v${version}";
    hash = "sha256-py4Zk6+6oS2nAhVsxx30TUkuABrvLB6ogZnYNiZJFG8=";
  };

  nativeBuildInputs = [
    nodejs
    pnpmConfigHook
    pnpm_9
    makeWrapper
  ];

  pnpmDeps = fetchPnpmDeps {
    inherit
      pname
      version
      src
      ;
    pnpm = pnpm_9;
    fetcherVersion = 1;
    hash = "sha256-CXeHNjzmAnaVnGL7yqXc/oBApKx6VyFoO09yah8M808=";
  };

  buildPhase = ''
    runHook preBuild

    pnpm build
    pnpm exec oclif manifest

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin
    mkdir -p $out/lib/simplelogin-cli

    cp -r node_modules $out/lib/simplelogin-cli/node_modules

    cp package.json $out/lib/simplelogin-cli/package.json
    cp -r dist $out/lib/simplelogin-cli/dist
    cp ./bin/run.js $out/lib/simplelogin-cli/run.js
    chmod +x $out/lib/simplelogin-cli/run.js

    makeWrapper ${nodejs}/bin/node $out/bin/sl \
      --add-flags $out/lib/simplelogin-cli/run.js

    runHook postInstall
  '';

  meta = {
    description = "Lightweight CLI tool to interact with the SimpleLogin.io API";
    homepage = "https://github.com/KennethWussmann/simplelogin-cli";
    license = lib.licenses.mit;
    mainProgram = "sl";
    maintainers = [];
  };
}
