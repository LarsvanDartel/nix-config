# lingarr — subtitle translation service, built natively (Vue client spliced into the ASP.NET wwwroot).
# Bump: update `version`/`hash`/`npmDepsHash`, then regenerate _lingarr/deps.json via `.fetch-deps`.
{...}: {
  nixpkgs.overlays = [
    (final: _prev: let
      version = "1.4.0";

      src = final.fetchFromGitHub {
        owner = "lingarr-translate";
        repo = "lingarr";
        tag = version;
        hash = "sha256-dT+7gnfIcW2Pe3U44/mD2BIx2qrz/ikRw8ZsgkCLdHA=";
      };

      client = final.buildNpmPackage {
        pname = "lingarr-client";
        inherit version;
        src = "${src}/Lingarr.Client";
        npmDepsHash = "sha256-Hn6fRsjTzo0Wiw4Sra8/MMupDMZ7T07iUDPMPEkwjBw=";
        installPhase = ''
          runHook preInstall
          cp -r dist $out
          runHook postInstall
        '';
      };
    in {
      lingarr = final.buildDotnetModule {
        pname = "lingarr";
        inherit version src;

        projectFile = "Lingarr.Server/Lingarr.Server.csproj";
        nugetDeps = ./_lingarr/deps.json;
        dotnet-sdk = final.dotnetCorePackages.sdk_10_0;
        dotnet-runtime = final.dotnetCorePackages.aspnetcore_10_0;
        dotnetFlags = ["-p:Version=${version}"];

        preBuild = ''
          mkdir -p Lingarr.Server/wwwroot
          cp -r ${client}/. Lingarr.Server/wwwroot/
          chmod -R u+w Lingarr.Server/wwwroot
        '';

        executables = ["Lingarr.Server"];

        passthru = {inherit client;};

        meta = {
          description = "Translate subtitle files with local and SaaS translation services";
          homepage = "https://github.com/lingarr-translate/lingarr";
          license = final.lib.licenses.agpl3Only;
          mainProgram = "Lingarr.Server";
          platforms = final.lib.platforms.linux;
        };
      };
    })
  ];
}
