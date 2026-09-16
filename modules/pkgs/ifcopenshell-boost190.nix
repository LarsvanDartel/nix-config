# ifcopenshell pinned to boost190 (nixpkgs default is boost191, which freecad
# pulls in transitively): 0.8.0 hits a deterministic ambiguous-overload error
# against boost 1.91's optional — same-shaped patch needed for the last few
# boost releases, i.e. recurring upstream lag. Drop once nixpkgs' own
# expression handles boost 1.91.
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
