{
  lib,
  stdenv,
  fetchFromGitHub,
  scons,
  python3,
  python3Packages,
  boost,
  protobuf,
  zlib,
  pkg-config,
  gperftools,
  libpng,
  hdf5,
  capstone,
  m4,
}:
stdenv.mkDerivation {
  pname = "gem5";
  version = "25.0.0.1";

  src = fetchFromGitHub {
    owner = "gem5";
    repo = "gem5";
    rev = "v25.0.0.1";
    sha256 = "sha256-cvJMe6VEKUE1vnS/IvZR2pBDvgw5KMaUBjx6ouUgmo4=";
  };

  nativeBuildInputs = [
    scons
    python3
    python3Packages.six
    python3Packages.pybind11
    python3Packages.setuptools
    pkg-config
    m4
  ];

  buildInputs = [
    boost
    protobuf
    zlib
    gperftools
    libpng
    hdf5
    capstone
  ];

  postPatch = ''
    patchShebangs .
  '';

  buildPhase = ''
    scons -j$NIX_BUILD_CORES build/X86/gem5.opt
  '';

  installPhase = ''
    mkdir -p $out/bin
    cp build/X86/gem5.opt $out/bin/
  '';

  meta = {
    description = "A modular platform for computer-system architecture research";
    homepage = "https://www.gem5.org";
    license = lib.licenses.bsd3;
    maintainers = [];
  };
}
