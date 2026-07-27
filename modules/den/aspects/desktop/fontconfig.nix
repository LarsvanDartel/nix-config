# desktop.fontconfig — bitmap font acceptance workaround.
{...}: {
  den.aspects.desktop.fontconfig.nixos = {...}: {
    fonts.fontconfig.localConf = ''
      <?xml version="1.0"?>
      <!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
      <fontconfig>
        <description>Accept bitmap fonts</description>
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
}
