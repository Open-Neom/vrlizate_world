import 'dart:convert';
import 'dart:io';

import 'package:vrlizate_world/vrlizate_world.dart';

/// Offline content compilation. This command never compiles executable Dart.
Future<void> main(List<String> args) async {
  if (args.contains('--help') || args.length != 2) {
    stdout.writeln(
      'Usage: dart run tool/pack_vrlw.dart INPUT.json OUTPUT.vrlw',
    );
    if (!args.contains('--help')) exitCode = 64;
    return;
  }
  try {
    final input = File(args[0]);
    final output = File(args[1]);
    if (!output.path.toLowerCase().endsWith('.vrlw')) {
      throw const FormatException('World packages use the .vrlw extension.');
    }
    if (await output.exists()) {
      throw const FileSystemException(
        'Output already exists; choose a new path.',
      );
    }
    if (await input.length() > 16 * 1024 * 1024) {
      throw const FormatException(
        'Authoring JSON exceeds the 16 MiB tool budget.',
      );
    }
    final json = jsonDecode(await input.readAsString());
    if (json is! Map<String, dynamic>) {
      throw const FormatException('Expected a world document object.');
    }
    final packed = VrlwBundleCodec.encode(json);
    final plain = VrlwBundleCodec.encode(json, compress: false);
    final header = VrlwBundleCodec.parseHeader(packed.sublist(0, 16));
    final index = VrlwBundleCodec.parseIndex(
      header,
      packed.sublist(16, header.payloadOffset),
    );
    await output.parent.create(recursive: true);
    await output.create(exclusive: true);
    await output.writeAsBytes(packed, flush: true);
    stdout.writeln(
      '${output.path}: ${packed.length} bytes; '
      '${index.chunks.length} independently readable regions.',
    );
    stdout.writeln(
      'STORE equivalent: ${plain.length} bytes; '
      'saving ${(100 * (1 - packed.length / plain.length)).toStringAsFixed(1)}%.',
    );
    stdout.writeln('Index SHA256: ${index.indexSha256}');
  } catch (error) {
    stderr.writeln('Cannot compile VRLW: $error');
    exitCode = 1;
  }
}
