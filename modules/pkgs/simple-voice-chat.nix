# simple-voice-chat — proximity voice chat for the Minecraft servers. A bare
# jar, not a packwiz entry: services/_minecraft/pack's pack is shared by
# every server, so per-server mods go through services.minecraft's
# `extraMods`. Pinned to an exact Modrinth version URL — the CDN is
# content-addressed per version, so it never moves (unlike the Discord asset
# in roles/desktop-home.nix). Server still accepts vanilla clients; they
# just cannot talk.
{...}: {
  nixpkgs.overlays = [
    (final: _prev: {
      simple-voice-chat = final.fetchurl {
        # `name` alone, deliberately — no pname/version: given all three, the
        # store path loses its `.jar`, Fabric ignores non-jar files silently,
        # and the server comes up "healthy" with no voice chat.
        name = "voicechat-fabric-2.6.22.jar";
        url = "https://cdn.modrinth.com/data/9eGKb6K1/versions/DKSq5wO6/voicechat-fabric-2.6.22%2B26.2.jar";
        hash = "sha256-G2qMbEHW1+2qEFQ6xiOnCwxg8i80VnlptpmcNFqid7I=";
      };
    })
  ];
}
