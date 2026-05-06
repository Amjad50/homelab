{ lib, device ? "/dev/vda", storageDevice ? null }:
{
  disko.devices = {
    disk = {
      main = {
        inherit device;
        type = "disk";
        content = {
          type = "gpt";
          partitions = {
            bios = {
              size = "1M";
              type = "EF02";
              priority = 1;
            };
            esp = {
              size = "512M";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot/efi";
                mountOptions = [ "fmask=0022" "dmask=0022" ];
              };
            };
            boot = {
              size = "1G";
              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = "/boot";
              };
            };
            root = {
              size = "100%";
              content = {
                type = "btrfs";
                extraArgs = [ "-f" ];
                subvolumes = {
                  "@" = {
                    mountpoint = "/";
                    mountOptions = [ "compress=zstd:3" "noatime" "space_cache=v2" ];
                  };
                  "@/.snapshots" = { };
                  "@home" = {
                    mountpoint = "/home";
                    mountOptions = [ "compress=zstd:1" "noatime" "space_cache=v2" ];
                  };
                  "@home/.snapshots" = { };
                  "@nix" = {
                    mountpoint = "/nix";
                    mountOptions = [ "compress=zstd:3" "noatime" "space_cache=v2" ];
                  };
                  "@var" = {
                    mountpoint = "/var";
                    mountOptions = [ "compress=zstd:1" "noatime" "space_cache=v2" ];
                  };
                  "@var-log" = {
                    mountpoint = "/var/log";
                    mountOptions = [ "compress=zstd:6" "noatime" "space_cache=v2" ];
                  };
                  "@var-log/.snapshots" = { };
                  "@var-cache" = {
                    mountpoint = "/var/cache";
                    mountOptions = [ "nodatacow" "noatime" "space_cache=v2" ];
                  };
                  "@var-tmp" = {
                    mountpoint = "/var/tmp";
                    mountOptions = [ "nodatacow" "noatime" "space_cache=v2" ];
                  };
                  "@var-lib" = {
                    mountpoint = "/var/lib";
                    mountOptions = [ "compress=zstd:1" "noatime" "space_cache=v2" ];
                  };
                  "@var-lib/.snapshots" = { };
                  "@var-lib-docker" = {
                    mountpoint = "/var/lib/docker";
                    mountOptions = [ "compress=zstd:1" "noatime" "space_cache=v2" ];
                  };
                  "@srv" = {
                    mountpoint = "/srv";
                    mountOptions = [ "compress=zstd:1" "noatime" "space_cache=v2" ];
                  };
                  "@opt" = {
                    mountpoint = "/opt";
                    mountOptions = [ "compress=zstd:1" "noatime" "space_cache=v2" ];
                  };
                  "@tmp" = {
                    mountpoint = "/tmp";
                    mountOptions = [ "nodatacow" "noatime" "space_cache=v2" ];
                  };
                };
              };
            };
          };
        };
      };

    } // lib.optionalAttrs (storageDevice != null) {
      storage = {
        device = storageDevice;
        type = "disk";
        content = {
          type = "gpt";
          partitions = {
            storage = {
              size = "100%";
              content = {
                type = "filesystem";
                format = "btrfs";
                mountpoint = "/mnt/storage";
                mountOptions = [ "compress=zstd:1" "noatime" "space_cache=v2" ];
              };
            };
          };
        };
      };
    };
  };
}
