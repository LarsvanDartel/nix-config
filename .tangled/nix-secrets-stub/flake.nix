# A stand-in for the private nix-secrets input, used only by CI.
#
# Every evaluation in this repo forces that input into the store, because
# core/sops.nix does `builtins.toString inputs.nix-secrets`. But sops-nix is
# configured with `validateSopsFiles = false`, so nothing ever stats, reads or
# decrypts anything inside it — the path only lands as a string in the sops
# manifest, and the file it names is opened at *activation* time on the host,
# from the real secrets that shipped with the closure.
#
# So an empty directory satisfies every check and every build. Verified rather
# than assumed: gaia's toplevel builds to completion against this.
#
# What that buys is the whole point — CI needs no credential at all. No deploy
# key, no repo secret, no read access to the fleet's encrypted secrets held by
# a build system. And it costs nothing in coverage, because pointing CI at the
# real repository would not validate one extra thing: with validateSopsFiles
# off, the real input is just as unread as this one.
#
# The one real difference is closure identity. A system built against this stub
# is byte-for-byte the deployed system *except* for the sops manifest, so CI's
# output cannot be reused to warm a deploy. That trade is only worth revisiting
# if the spindle ever pushes to attic — see the uploadUrl note in
# services/tangled.nix, which is deliberately unset for its own reasons.
{
  description = "Empty stand-in for nix-secrets, for credential-free CI";
  outputs = _: {};
}
