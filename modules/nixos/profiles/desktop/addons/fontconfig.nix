{...}: {
  flake.modules.nixos.desktop = {...}: {
    fonts.fontconfig = {
      # FIXME: Fixes https://github.com/NixOS/nixpkgs/issues/449657
      localConf = ''
        <?xml version="1.0"?>
        <!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
        <fontconfig>
          <description>Accept bitmap fonts</description>
        <!-- Accept bitmap fonts -->
         <selectfont>
          <acceptfont>
           <pattern>
             <patelt name="outline"><bool>false</bool></patelt>
           </pattern>
          </acceptfont>
         </selectfont>
        </fontconfig>
      '';
    };
  };
}
