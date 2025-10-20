{
  disko.devices = {
    disk = let
      mkZfsDevice = device: {
        type = "disk";
        inherit device;
        content = {
          type = "gpt";
          partitions = {
            zfs = {
              size = "100%";
              content = {
                type = "zfs";
                pool = "tank";
              };
            };
          };
        };
      };
    in {
      main = {
        type = "disk";
        device = "/dev/disk/by-id/ata-Samsung_SSD_850_EVO_M.2_250GB_S33CNX0H704432H";
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              size = "512M";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = ["umask=0077"];
              };
            };
            root = {
              size = "100%";
              content = {
                type = "btrfs";
                extraArgs = ["-L" "nixos" "-f"];
                subvolumes = {
                  "/root" = {
                    mountpoint = "/";
                    mountOptions = [
                      "compress=zstd"
                    ];
                  };
                  "/nix" = {
                    mountpoint = "/nix";
                    mountOptions = [
                      "subvol=nix"
                      "compress=zstd"
                      "noatime"
                    ];
                  };
                  "/persist" = {
                    mountpoint = "/persist";
                    mountOptions = [
                      "subvol=persist"
                      "compress=zstd"
                      "noatime"
                    ];
                  };
                };
              };
            };
          };
        };
      };
      data0 = mkZfsDevice "/dev/disk/by-id/wwn-0x5000cca02f3c5fa8";
      data1 = mkZfsDevice "/dev/disk/by-id/wwn-0x5000c500a024a4ef";
      data2 = mkZfsDevice "/dev/disk/by-id/wwn-0x5000c500a0273e73";
      data3 = mkZfsDevice "/dev/disk/by-id/wwn-0x5000c500a02712bb";
      data4 = mkZfsDevice "/dev/disk/by-id/wwn-0x5000c500a0247b63";
      data5 = mkZfsDevice "/dev/disk/by-id/wwn-0x5000c500a0273f2b";

      spare = mkZfsDevice "/dev/disk/by-id/wwn-0x5000cca02f3cabb0";
      cache = mkZfsDevice "/dev/disk/by-id/wwn-0x50014ee65bf3c65a";
    };

    zpool = {
      tank = {
        type = "zpool";
        mode = {
          topology = {
            type = "topology";
            vdev = [
              {
                mode = "raidz1";
                members = ["data0" "data1" "data2"];
              }
              {
                mode = "raidz1";
                members = ["data3" "data4" "data5"];
              }
            ];
            spare = ["spare"];
            cache = ["cache"];
          };
        };
        rootFsOptions = {
          compression = "zstd";
          "com.sun:auto-snapshot" = "false";
        };
        datasets = {
          encrypted = {
            type = "zfs_fs";
            options = {
              mountpoint = "none";
              encryption = "aes-256-gcm";
              keyformat = "raw";
              keylocation = "file:///run/keys/zfs-tank.key";
            };
          };
          "encrypted/main" = {
            type = "zfs_fs";
            options = {
              mountpoint = "/tank/crypted";
              "com.sun:auto-snapshot" = "true";
            };
          };
        };
      };
    };
  };
}
