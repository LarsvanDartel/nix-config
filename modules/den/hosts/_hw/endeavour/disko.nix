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
          "media" = {
            type = "zfs_fs";
            options = {
              mountpoint = "/tank/media";
              "com.sun:auto-snapshot" = "false";
            };
          };

          # The binary cache's chunk store, tuned for what it actually is.
          #
          # recordsize 1M matches the chunk sizes set in services/attic.nix; at
          # the pool default of 128K every chunk was several records and so
          # several IOs on a raidz1 stripe.
          #
          # sync=disabled is the significant one and is safe *here* specifically
          # because every byte in this dataset is reproducible: it is a cache of
          # build outputs that exist in the stores that pushed them. The pool
          # has no SLOG, so honouring sync meant a ZIL round trip across
          # spinning disks per chunk — measured at ~150 KB/s ingest against a
          # 24 MB/s link. The exposure is that a power loss can lose the last
          # few seconds of uploads, which costs a re-push and nothing else.
          #
          # Not snapshotted for the same reason: there is nothing here worth
          # keeping a history of.
          "atticd" = {
            type = "zfs_fs";
            options = {
              mountpoint = "/tank/atticd";
              recordsize = "1M";
              sync = "disabled";
              "com.sun:auto-snapshot" = "false";
            };
          };
        };
      };
    };
  };
}
