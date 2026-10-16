import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vrlizate_world/vrlizate_world.dart';

// CPU microbenchmark, not a renderer, FPS test, or estimate of phone timing.
// Run from the package root. For AOT:
// dart compile exe tool/benchmark_vrlw.dart -o /tmp/benchmark_vrlw
// /tmp/benchmark_vrlw --runtime-label AOT
void main(List<String> args) {
  try {
    final options = _Options.parse(args);
    if (options == null) return;
    final forest = File(options.forestPath).readAsBytesSync();
    final cases = <_Case>[
      _Case('forest (1,1)', forest, x: 1, z: 1),
      for (final count in [256, 4096])
        for (final compress in [true, false])
          _Case(
            'synthetic $count ${compress ? 'deflate' : 'store'}',
            VrlwBundleCodec.encode(_synthetic(count), compress: compress),
          ),
    ];

    stdout.writeln('VRLW selected-region CPU benchmark');
    stdout.writeln('UTC: ${DateTime.now().toUtc().toIso8601String()}');
    stdout.writeln('Runtime label: ${options.runtimeLabel}');
    stdout.writeln('Dart: ${Platform.version}');
    stdout.writeln('OS: ${Platform.operatingSystemVersion}');
    stdout.writeln('Logical CPUs: ${Platform.numberOfProcessors}');
    stdout.writeln('Stopwatch frequency: ${Stopwatch().frequency} ticks/s');
    stdout.writeln(
      'Per operation: ${options.warmup} warmups, '
      '${options.samples} measured samples. Percentiles use nearest rank.',
    );
    stdout.writeln(
      'No file/network reads, encoding, rendering, or GPU work are timed. '
      'Each sample performs one operation; GC and scheduler pauses remain.',
    );
    stdout.writeln(
      'Index timing: parseIndex on pre-read index bytes. '
      'Chunk timing: SHA-256 + inflate (if used) + JSON + entity validation '
      'and construction; pre-parsed index and pre-read selected block.',
    );

    var checksum = 0;
    for (final item in cases) {
      final indexStats = _measure(options, () {
        final index = VrlwBundleCodec.parseIndex(item.header, item.indexBytes);
        checksum += index.chunks.length;
      });
      final chunkStats = _measure(options, () {
        final entities = item.decode();
        checksum += entities.length;
      });
      final count = item.decode().length;
      final savings =
          (1 - item.chunk.packedBytes / item.chunk.unpackedBytes) * 100;
      stdout.writeln('\n${item.name}');
      stdout.writeln('  index SHA-256: ${item.index.indexSha256}');
      stdout.writeln(
        '  file=${item.bytes.length} B; header+index='
        '${item.header.payloadOffset} B; regions=${item.index.chunks.length}',
      );
      stdout.writeln(
        '  selected region: $count entities; codec=${item.chunk.codec}; '
        'packed=${item.chunk.packedBytes} B; '
        'decoded JSON=${item.chunk.unpackedBytes} B; '
        'payload savings=${savings.toStringAsFixed(1)}%',
      );
      stdout.writeln('  index parse: $indexStats');
      stdout.writeln('  chunk decode: $chunkStats');
    }
    stdout.writeln('\nResult checksum: $checksum');
    stdout.writeln(
      'Byte counts describe serialized data, not decoded heap or GPU memory. '
      'Results apply only to this runtime/device; they do not measure FPS.',
    );
  } catch (error) {
    stderr.writeln('Cannot benchmark VRLW: $error');
    exitCode = 1;
  }
}

Map<String, Object?> _synthetic(int count) => {
  'schemaVersion': 1,
  'id': 'benchmark.synthetic',
  'title': 'Deterministic $count-entity benchmark',
  'revision': '1.0.0',
  'license': 'Apache-2.0',
  'gridId': 'benchmark-12m',
  'cellSizeMeters': 12,
  'origin': {'type': 'local'},
  'prototypes': ['openworld.tree'],
  'regions': [
    {
      'x': 0,
      'z': 0,
      'entities': [
        for (var i = 0; i < count; i++)
          {
            'id': 'tree:$i',
            'prototypeId': 'openworld.tree',
            // A deterministic 64 x 64 grid strictly inside the region.
            'x': ((i % 64) + .5) * 12 / 64,
            'y': 0,
            'z': ((i ~/ 64) + .5) * 12 / 64,
            'yawRadians': (i % 8) * math.pi / 4,
            'scale': 1 + (i % 4) * .25,
          },
      ],
    },
  ],
};

final class _Case {
  _Case(this.name, this.bytes, {int x = 0, int z = 0}) {
    header = VrlwBundleCodec.parseHeader(
      Uint8List.sublistView(bytes, 0, VrlwBundleCodec.headerSize),
    );
    if (header.totalLength != bytes.length) {
      throw const FormatException('Fixture size does not match header.');
    }
    indexBytes = Uint8List.sublistView(
      bytes,
      VrlwBundleCodec.headerSize,
      header.payloadOffset,
    );
    index = VrlwBundleCodec.parseIndex(header, indexBytes);
    chunk =
        index.chunkAt(x, z) ??
        (throw FormatException('Fixture has no region ($x,$z).'));
    packedBytes = Uint8List.sublistView(
      bytes,
      header.payloadOffset + chunk.offset,
      header.payloadOffset + chunk.offset + chunk.packedBytes,
    );
    world = VrWorldAddress(worldId: index.id, instanceId: 'benchmark');
    decode(); // Validate fixtures before warmup and timing.
  }

  final String name;
  final Uint8List bytes;
  late final VrlwBundleHeader header;
  late final Uint8List indexBytes;
  late final VrlwBundleIndex index;
  late final VrlwChunkIndex chunk;
  late final Uint8List packedBytes;
  late final VrWorldAddress world;

  List<VrWorldEntity> decode() => VrlwBundleCodec.decodeChunk(
    index,
    chunk,
    packedBytes,
    world: world,
    registeredPrototypeIds: const {'openworld.tree'},
  );
}

_Stats _measure(_Options options, void Function() operation) {
  for (var i = 0; i < options.warmup; i++) {
    operation();
  }
  final ticks = <int>[];
  final watch = Stopwatch();
  for (var i = 0; i < options.samples; i++) {
    watch.reset();
    watch.start();
    operation();
    watch.stop();
    ticks.add(watch.elapsedTicks);
  }
  ticks.sort();
  double percentile(double p) =>
      ticks[(p * ticks.length).ceil() - 1] * 1000 / watch.frequency;
  return _Stats(percentile(.5), percentile(.95));
}

final class _Stats {
  const _Stats(this.p50, this.p95);
  final double p50;
  final double p95;

  @override
  String toString() =>
      'p50=${p50.toStringAsFixed(3)} ms; p95=${p95.toStringAsFixed(3)} ms';
}

final class _Options {
  const _Options({
    required this.forestPath,
    required this.runtimeLabel,
    required this.samples,
    required this.warmup,
  });

  final String forestPath;
  final String runtimeLabel;
  final int samples;
  final int warmup;

  static _Options? parse(List<String> args) {
    if (args.contains('--help')) {
      stdout.writeln(
        'Usage: dart run tool/benchmark_vrlw.dart '
        '[--forest tool/fixtures/forest.vrlw] [--samples 200] [--warmup 30] '
        '[--runtime-label JIT-or-AOT]\n'
        'Samples: 20..5000; warmup: 1..1000. Run from the package root.',
      );
      return null;
    }
    final values = <String, String>{};
    const allowed = {'--forest', '--samples', '--warmup', '--runtime-label'};
    for (var i = 0; i < args.length; i += 2) {
      if (!allowed.contains(args[i]) ||
          i + 1 >= args.length ||
          values.containsKey(args[i])) {
        throw ArgumentError('Expected unique option/value pairs; use --help.');
      }
      values[args[i]] = args[i + 1];
    }
    final samples = int.parse(values['--samples'] ?? '200');
    final warmup = int.parse(values['--warmup'] ?? '30');
    if (samples < 20 || samples > 5000 || warmup < 1 || warmup > 1000) {
      throw ArgumentError('Samples: 20..5000; warmup: 1..1000.');
    }
    return _Options(
      forestPath: values['--forest'] ?? 'tool/fixtures/forest.vrlw',
      runtimeLabel: values['--runtime-label'] ?? 'unspecified',
      samples: samples,
      warmup: warmup,
    );
  }
}
