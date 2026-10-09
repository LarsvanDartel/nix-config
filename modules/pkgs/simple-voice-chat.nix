# simple-voice-chat — proximity voice chat for the Minecraft servers. A bare
# jar via services.minecraft's `extraMods`, not packwiz: the pack is shared
# by every server.
{...}: {
  nixpkgs.overlays = [
    (final: _prev: {
      simple-voice-chat = final.fetchurl {
        # `name` alone, deliberately: with pname/version the store path loses
        # `.jar` and Fabric silently ignores it.
        name = "voicechat-fabric-2.6.22.jar";
        url = "https://cdn.modrinth.com/data/9eGKb6K1/versions/DKSq5wO6/voicechat-fabric-2.6.22%2B26.2.jar";
        hash = "sha256-G2qMbEHW1+2qEFQ6xiOnCwxg8i80VnlptpmcNFqid7I=";
      };
    })
  ];
}
