import 'dart:io';

import 'package:vrlizate_world/vrlizate_world.dart';
import 'package:vrlizate_world/vrlizate_world_io.dart';

Future<void> main(List<String> args) async {
  if (args.length != 3 || args.contains('--help')) {
    stdout.writeln(
      'Usage: dart run tool/read_vrlw.dart FILE.vrlw CELL_X CELL_Z',
    );
    if (!args.contains('--help')) exitCode = 64;
    return;
  }
  VrlwByteSource? source;
  try {
    source = await VrlwFileSource.open(args[0]);
    final reader = await VrlwPlaceReader.open(
      source,
      registeredPrototypeIds: const {'openworld.tree'},
    );
    final provider = VrlwRegionProvider(reader);
    final x = int.parse(args[1]), z = int.parse(args[2]);
    final cache = VrRegionCache<List<VrWorldEntity>>(
      grid: provider.grid,
      provider: provider.load,
      prefetchRadiusCells: 0,
      retentionRadiusCells: 0,
    );
    cache.updatePosition(
      VrWorldPosition(
        (x + .5) * provider.grid.cellSizeMeters,
        1.6,
        (z + .5) * provider.grid.cellSizeMeters,
      ),
    );
    await cache.waitForIdle();
    final snapshot = cache.snapshot;
    if (snapshot.errors.isNotEmpty) throw snapshot.errors.values.first;
    stdout.writeln(
      '${reader.index.title}: '
      '${snapshot.currentData!.value.length} entities in ($x, $z).',
    );
    stdout.writeln(
      'Read ${16 + reader.index.header.manifestLength} index bytes '
      '+ ${provider.sourceBytes} region bytes of ${source.length} total.',
    );
    cache.dispose();
  } catch (error) {
    stderr.writeln('Cannot read VRLW: $error');
    exitCode = 1;
  } finally {
    await source?.close();
  }
}
