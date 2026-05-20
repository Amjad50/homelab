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
}
