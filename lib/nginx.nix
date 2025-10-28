_: let
  inherit (builtins) toString;
in {
  createProxy = let
    base = locations: {
      inherit locations;

      forceSSL = true;
      enableACME = true;
    };
  in
    port:
      base {
        "/".proxyPass = "http://127.0.0.1:" + toString port + "/";
      };
}
