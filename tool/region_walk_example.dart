import 'package:vrlizate_world/vrlizate_world.dart';

/// Demonstrates a long walk without enumerating/loading the entire world.
/// Descriptors are synthetic; a host can wrap this provider with disk/HTTP.
Future<void> main() async {
  var loads = 0;
  var peakEntries = 0;
  final cache = VrRegionCache<String>(
    grid: VrRegionGrid(
      world: VrWorldAddress(worldId: 'walk-demo', instanceId: 'local'),
      gridId: 'origin0-12m-v1',
      cellSizeMeters: 12,
    ),
    provider: (key, cancellation) async {
      cancellation.throwIfCancelled();
      loads++;
      return VrRegionData(value: 'terrain:${key.x}:${key.z}', sizeBytes: 1024);
    },
    maxEntries: 16,
    maxBytes: 16 * 1024,
    prefetchRadiusCells: 1,
    retentionRadiusCells: 1,
  );
  for (var x = 0; x < 1000; x++) {
    cache.updatePosition(VrWorldPosition(x * 12, 1.6, 0));
    await cache.waitForIdle();
    final size = cache.snapshot.resident.length;
    if (size > peakEntries) peakEntries = size;
  }
  final beforeReturn = loads;
  cache.updatePosition(VrWorldPosition(998 * 12, 1.6, 0));
  await cache.waitForIdle();
  print('1,000 regions traversed; peak resident regions: $peakEntries.');
  print('Provider loads on nearby return: ${loads - beforeReturn}.');
  print('Resident descriptor bytes: ${cache.snapshot.residentBytes}.');
  print('This measures cache bounds and reuse, not rendered VR FPS.');
  cache.dispose();
}
