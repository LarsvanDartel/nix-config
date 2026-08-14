# simple-voice-chat — proximity voice chat for the Minecraft servers.
#
# A bare jar rather than a packwiz entry, and that is the interesting decision.
# The packwiz pack in services/_minecraft/pack is *shared* by every server this
# fleet runs, because it exists to carry the performance mods that all of them
# want. Voice chat is wanted on one server, so putting it there would install
# it everywhere — hence services.minecraft's per-server `extraMods`, which this
# feeds.
#
# Pinned to an exact Modrinth version URL. Modrinth's CDN is content-addressed
# per version, so the URL never changes under us the way the Discord asset in
# roles/desktop-home.nix does; upgrading is editing the version and the hash
# together, which is the point.
#
# Client side is optional: a server running this still accepts vanilla clients,
# they simply cannot talk. Players who want voice install the same mod from
# Modrinth — the version must match the server's major version.
{...}: {
  nixpkgs.overlays = [
    (final: _prev: {
      simple-voice-chat = final.fetchurl {
        # `name` alone, deliberately — no pname/version. Given all three,
        # fetchurl builds the store path from pname+version and the store path
        # ends up `…-simple-voice-chat-2.6.22+26.2`, with no `.jar`. Fabric
        # loads `*.jar` and ignores everything else without a word, so the
        # server would have come up looking healthy with no voice chat at all.
        name = "voicechat-fabric-2.6.22.jar";
        url = "https://cdn.modrinth.com/data/9eGKb6K1/versions/DKSq5wO6/voicechat-fabric-2.6.22%2B26.2.jar";
        hash = "sha256-G2qMbEHW1+2qEFQ6xiOnCwxg8i80VnlptpmcNFqid7I=";
      };
    })
  ];
}
