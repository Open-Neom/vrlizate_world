import 'dart:io';

import 'package:vrlizate_world/vrlizate_world.dart';
import 'package:vrlizate_world/vrlizate_world_io.dart';

/// Data-only example: the rendering host supplies the tree's geometry/material.
Future<void> main(List<String> args) async {
  if (args.length != 1 && args.length != 2) {
    stderr.writeln('Usage: read_garden.dart FILE.vrlw [TRUSTED_INDEX_SHA256]');
    exitCode = 64;
    return;
  }
  VrlwByteSource? source;
  VrlwPlaceReader? reader;
  VrRegionCache<List<VrWorldEntity>>? cache;
  try {
    source = await VrlwFileSource.open(args.first);
    reader = await VrlwPlaceReader.open(
      source,
      registeredPrototypeIds: const {'openworld.tree'},
      instanceId: 'local-example',
      expectedIndexSha256: args.length == 2 ? args[1] : null,
    );
    final provider = VrlwRegionProvider(reader);
    cache = VrRegionCache<List<VrWorldEntity>>(
      grid: provider.grid,
      provider: provider.load,
      prefetchRadiusCells: 0,
      retentionRadiusCells: 0,
      maxConcurrentLoads: 1,
      maxEntries: 4,
      maxBytes: 2 * 1024 * 1024,
    );
    cache.updatePosition(VrWorldPosition(2, 1.6, 3));
    await cache.waitForIdle();
    final snapshot = cache.snapshot;
    if (snapshot.errors.isNotEmpty) throw snapshot.errors.values.first;
    final registry = VrWorldRegistry(world: reader.world, maxEntities: 4096);
    // Registry admission also rejects duplicate IDs across resident regions.
    for (final region in snapshot.resident.values) {
      for (final entity in region.value) {
        registry.add(entity);
      }
    }
    stdout.writeln('${reader.index.title}: ${registry.length} entities.');
    for (final entity in registry.entities) {
      final position = entity.transform.position;
      stdout.writeln(
        '${entity.id}: ${entity.prototypeId} '
        'at (${position.x}, ${position.y}, ${position.z}), '
        'scale=${entity.transform.scale}',
      );
    }
    stdout.writeln('Index SHA256: ${reader.index.indexSha256}');
    stdout.writeln('Region bytes read: ${provider.sourceBytes}');
  } catch (error) {
    stderr.writeln('Cannot open garden: $error');
    exitCode = 1;
  } finally {
    cache?.dispose();
    if (reader != null) {
      await reader.close();
    } else {
      await source?.close();
    }
  }
}
