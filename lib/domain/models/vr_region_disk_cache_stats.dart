/// A snapshot of managed on-disk entries, including envelope bytes.
final class VrRegionDiskCacheStats {
  const VrRegionDiskCacheStats({
    required this.entryCount,
    required this.totalBytes,
    required this.hits,
    required this.misses,
    required this.evictions,
  });

  final int entryCount;
  final int totalBytes;

  /// Counters cover this cache object's lifetime, not earlier app launches.
  final int hits;
  final int misses;
  final int evictions;
}
