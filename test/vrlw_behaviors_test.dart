import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:vrlizate_world/vrlizate_world.dart';

import 'vrlw_bundle_test.dart' as bundle;
import 'vrlw_resources_test.dart' as resources;

Map<String, Object?> _motion({
  String id = 'rotor',
  String node = 'rotor-node',
}) => {
  'id': id,
  'prototypeId': 'tree',
  'node': node,
  'kind': 'spin',
  'axis': 'y',
  'periodSeconds': 12,
};

Map<String, Object?> _interaction({String id = 'rotor-switch'}) => {
  'id': id,
  'label': 'Activar rotor',
  'position': [-62, 1.2, 132],
  'action': 'toggleMotion',
  'target': 'rotor',
};

Map<String, Object?> _source() {
  final wav = Uint8List(44);
  ByteData.sublistView(wav)
    ..setUint32(0, 0x46464952, Endian.little)
    ..setUint32(8, 0x45564157, Endian.little);
  return resources.resourceSource()
    ..['motions'] = [_motion()]
    ..['interactions'] = [_interaction()]
    ..['resources'] = [
      ...(resources.resourceSource()['resources'] as List),
      {'id': 'ambience', 'type': 'audio.wav', 'data': base64.encode(wav)},
    ]
    ..['audioEmitters'] = [
      {'id': 'courtyard', 'resource': 'ambience', 'x': -62, 'y': 1, 'z': 132},
    ];
}

Map<String, Object?> _first(Map<String, Object?> document, String key) =>
    (document[key] as List).first as Map<String, Object?>;

/// Both authoring and untrusted indexed bytes must enforce the same contract.
void _rejectBoth(void Function(Map<String, Object?>) mutate) {
  final source = _source();
  mutate(source);
  expect(() => VrlwBundleCodec.encode(source), throwsFormatException);

  final baseline = VrlwBundleCodec.encode(_source());
  final index = bundle.indexOf(baseline);
  final manifest = bundle.indexJson(baseline);
  mutate(manifest);
  final malformed = bundle.makeBundle(
    manifest,
    baseline.sublist(index.header.payloadOffset),
  );
  expect(() => bundle.indexOf(malformed), throwsFormatException);
}

void main() {
  for (final compress in [false, true]) {
    test('portable spin, bob and nearby actions roundtrip ($compress)', () {
      final source = _source();
      (source['motions'] as List).add({
        ..._motion(id: 'beacon', node: 'beacon-node'),
        'kind': 'bob',
        'axis': 'z',
        'pivot': [1, 2, 3],
        'periodSeconds': 2,
        'amplitude': 0.5,
        'rangeMeters': 48,
        'initiallyEnabled': false,
      });
      (source['interactions'] as List).add({
        ..._interaction(id: 'audio-switch'),
        'label': 'Sonido del patio',
        'action': 'toggleAudio',
        'target': 'courtyard',
        'maxDistance': 4,
      });
      final bytes = VrlwBundleCodec.encode(source, compress: compress);
      final index = bundle.indexOf(bytes);
      expect(index.motions, hasLength(2));
      final spin = index.motions.first;
      expect((spin.kind, spin.axis, spin.periodSeconds), ('spin', 'y', 12));
      expect(spin.pivot, [0, 0, 0]);
      expect(spin.amplitude, isNull);
      expect(spin.rangeMeters, 32);
      expect(spin.initiallyEnabled, isTrue);
      final bob = index.motions.last;
      expect(
        (bob.amplitude, bob.rangeMeters, bob.initiallyEnabled),
        (0.5, 48, false),
      );
      expect(bob.pivot, [1, 2, 3]);
      expect(index.interactions.first.maxDistance, 3);
      expect(index.interactions.last.action, 'toggleAudio');
      expect(index.interactions.last.position, [-62, 1.2, 132]);
      expect(() => index.motions.clear(), throwsUnsupportedError);
      expect(() => spin.pivot[0] = 5, throwsUnsupportedError);
      expect(
        () => index.interactions.first.position[0] = 5,
        throwsUnsupportedError,
      );
    });
  }

  test('empty additions preserve historical bytes and absent arrays', () {
    final source = resources.resourceSource();
    final baseline = VrlwBundleCodec.encode(source);
    source['motions'] = [];
    source['interactions'] = [];
    final bytes = VrlwBundleCodec.encode(source);
    expect(bytes, baseline);
    final index = bundle.indexOf(bytes);
    expect(index.motions, isEmpty);
    expect(index.interactions, isEmpty);
    expect(bundle.indexJson(bytes).containsKey('motions'), isFalse);
    expect(bundle.indexJson(bytes).containsKey('interactions'), isFalse);
  });

  test('model vectors copy their inputs and export typed JSON', () {
    final pivot = <double>[1, 2, 3];
    final motion = VrlwMotionSpec(
      id: 'bell',
      prototypeId: 'tree',
      node: 'bell-node',
      kind: 'bob',
      axis: 'y',
      periodSeconds: 6,
      amplitude: 0.1,
      pivot: pivot,
    );
    final interaction = VrlwInteractionSpec(
      id: 'switch',
      label: 'Campana',
      position: pivot,
      action: 'toggleMotion',
      target: 'bell',
    );
    pivot[0] = 99;
    expect(motion.pivot, [1, 2, 3]);
    expect(interaction.position, [1, 2, 3]);
    expect(motion.toJson()['amplitude'], 0.1);
    expect(interaction.toJson()['target'], 'bell');
  });

  test('limits allow exactly eight motions and eight interactions', () {
    final source = _source()
      ..['motions'] = List.generate(
        8,
        (i) => _motion(id: 'motion-$i', node: 'node-$i'),
      )
      ..['interactions'] = List.generate(
        8,
        (i) => {..._interaction(id: 'switch-$i'), 'target': 'motion-$i'},
      );
    final index = bundle.indexOf(VrlwBundleCodec.encode(source));
    expect(index.motions, hasLength(8));
    expect(index.interactions, hasLength(8));
  });

  final invalid = <String, void Function(Map<String, Object?>)>{
    'unknown top-level executable field': (d) => d['script'] = 'run()',
    'unknown motion executable field': (d) =>
        _first(d, 'motions')['script'] = 'run()',
    'unknown interaction field': (d) =>
        _first(d, 'interactions')['url'] = 'https://invalid.test',
    'unsupported motion kind': (d) => _first(d, 'motions')['kind'] = 'walk',
    'unsupported motion axis': (d) => _first(d, 'motions')['axis'] = 'xyz',
    'undeclared motion prototype': (d) =>
        _first(d, 'motions')['prototypeId'] = 'absent',
    'prototype without packaged model': (d) => d['prototypeBindings'] = [],
    'non-ASCII node name': (d) => _first(d, 'motions')['node'] = 'hélice',
    'node path is not an identifier': (d) =>
        _first(d, 'motions')['node'] = '../node',
    'duplicate motion ID': (d) =>
        (d['motions'] as List).add(_motion(node: 'another-node')),
    'two motions on same model node': (d) =>
        (d['motions'] as List).add(_motion(id: 'another')),
    'nine motions': (d) =>
        d['motions'] = List.generate(9, (i) => _motion(id: 'm$i', node: 'n$i')),
    'period too short': (d) => _first(d, 'motions')['periodSeconds'] = 1.999,
    'period too long': (d) => _first(d, 'motions')['periodSeconds'] = 120.001,
    'spin cannot accept amplitude': (d) =>
        _first(d, 'motions')['amplitude'] = 0.1,
    'bob needs amplitude': (d) => _first(d, 'motions')['kind'] = 'bob',
    'bob displacement too large': (d) =>
        _first(d, 'motions').addAll({'kind': 'bob', 'amplitude': 0.501}),
    'bob displacement zero': (d) =>
        _first(d, 'motions').addAll({'kind': 'bob', 'amplitude': 0}),
    'pivot outside model range': (d) =>
        _first(d, 'motions')['pivot'] = [32.001, 0, 0],
    'pivot invalid shape': (d) => _first(d, 'motions')['pivot'] = [0, 0],
    'range too small': (d) => _first(d, 'motions')['rangeMeters'] = 3.999,
    'range too large': (d) => _first(d, 'motions')['rangeMeters'] = 48.001,
    'null optional range': (d) => _first(d, 'motions')['rangeMeters'] = null,
    'nonboolean enabled': (d) => _first(d, 'motions')['initiallyEnabled'] = 1,
    'null enabled': (d) => _first(d, 'motions')['initiallyEnabled'] = null,
    'unknown motion action target': (d) =>
        _first(d, 'interactions')['target'] = 'absent',
    'motion cannot target audio': (d) =>
        _first(d, 'interactions')['target'] = 'courtyard',
    'audio cannot target motion': (d) =>
        _first(d, 'interactions')['action'] = 'toggleAudio',
    'unsupported action': (d) =>
        _first(d, 'interactions')['action'] = 'launchUrl',
    'duplicate interaction ID': (d) =>
        (d['interactions'] as List).add(_interaction()),
    'nine interactions': (d) =>
        d['interactions'] = List.generate(9, (i) => _interaction(id: 's$i')),
    'interaction beyond indexed region': (d) =>
        _first(d, 'interactions')['position'] = [0, 1, 132],
    'interaction outside lower edge': (d) =>
        _first(d, 'interactions')['position'] = [-64.001, 1, 132],
    'interaction invalid position': (d) =>
        _first(d, 'interactions')['position'] = [1, 2],
    'interaction too far': (d) =>
        _first(d, 'interactions')['maxDistance'] = 4.001,
    'interaction negative reach': (d) =>
        _first(d, 'interactions')['maxDistance'] = -1,
    'null reach': (d) => _first(d, 'interactions')['maxDistance'] = null,
    'blank label': (d) => _first(d, 'interactions')['label'] = ' ',
    'long label': (d) => _first(d, 'interactions')['label'] = 'a' * 81,
    'control in label': (d) =>
        _first(d, 'interactions')['label'] = 'Hola\nMundo',
  };
  for (final entry in invalid.entries) {
    test(
      'strict writer/reader reject ${entry.key}',
      () => _rejectBoth(entry.value),
    );
  }

  test(
    'interaction includes indexed lower edge with negative cell coordinates',
    () {
      final source = _source();
      _first(source, 'interactions')['position'] = [-64, 0, 128];
      final index = bundle.indexOf(VrlwBundleCodec.encode(source));
      expect(index.interactions.single.position, [-64, 0, 128]);
    },
  );

  test('nonfinite runtime numbers fail writer before JSON serialization', () {
    for (final value in [
      double.nan,
      double.infinity,
      double.negativeInfinity,
    ]) {
      final source = _source();
      _first(source, 'motions')['periodSeconds'] = value;
      expect(() => VrlwBundleCodec.encode(source), throwsFormatException);
      final positionSource = _source();
      _first(positionSource, 'interactions')['position'] = [-62, value, 132];
      expect(
        () => VrlwBundleCodec.encode(positionSource),
        throwsFormatException,
      );
    }
  });
}
