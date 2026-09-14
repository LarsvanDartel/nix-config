# ifcopenshell — pinned to boost190 rather than nixpkgs' current default
# (boost191), which freecad (voyager's only consumer of either) pulls in
# transitively.
#
# ifcopenshell 0.8.0 fails to compile against boost 1.91's `optional`: several
# translation units in IfcCShapeProfileDef.cpp hit a genuine, deterministic
# ambiguous-overload error resolving a brace-init list against
# `boost::optional<double>`'s constructors — not a parallel-build race, it
# reproduces identically on every rebuild. ifcopenshell has needed a
# same-shaped patch for boost's last few releases (see the boost-1.86 patches
# and the boost189 CMakeLists workaround already in nixpkgs' own expression),
# so this is a recurring upstream lag rather than a one-off. Drop this once
# nixpkgs' ifcopenshell expression itself is updated for boost 1.91.
{...}: {
  nixpkgs.overlays = [
    (final: prev: {
      pythonPackagesExtensions =
        prev.pythonPackagesExtensions
        ++ [
          (_pyFinal: pyPrev: {
            ifcopenshell = pyPrev.ifcopenshell.override {boost = final.boost190;};
          })
        ];
    })
  ];
}
