{ ... }:
{
  zramSwap = {
    enable = true;
    algorithm = "zstd";
    # Default is ~50% of RAM. With 11.4 GiB total we get ~8 GiB virtual swap
    # which compresses to roughly 2.5–3 GiB physical at zstd ratios.
    memoryPercent = 70;
  };

  # zram is RAM-backed compression, not a slow disk. Bias the kernel toward
  # pushing cold anonymous pages out and waking kswapd earlier so we stop
  # hitting full memory-pressure stalls.
  boot.kernel.sysctl = {
    "vm.swappiness" = 100;
    "vm.vfs_cache_pressure" = 50;
    "vm.watermark_scale_factor" = 200;
  };

  # 2026-06-10 incident: opencloud postprocessing exhausted RAM+zram and the
  # host livelocked (pingable, no userspace) without any OOM kill. The kernel
  # OOM killer never triggered and systemd-oomd started before zram0 existed
  # ("No swap; memory pressure usage will be degraded") and only watches user
  # slices, not docker cgroups. earlyoom watches global MemAvailable/swap and
  # kills the largest process before the thrash point.
  services.earlyoom = {
    enable = true;
    freeMemThreshold = 10; # SIGTERM biggest process below 10% MemAvailable...
    freeSwapThreshold = 10; # ...AND below 10% free swap (zram full = 0%)
    freeMemKillThreshold = 5; # escalate to SIGKILL
    freeSwapKillThreshold = 5;
    extraArgs = [
      "--avoid"
      "(^|/)(init|systemd.*|sshd|dockerd|containerd|containerd-shim.*|journald)$"
      "--prefer"
      "(^|/)(java|clamd|opencloud|node|jellyfin|immich.*)$"
    ];
  };
  systemd.oomd.enable = false;
}
