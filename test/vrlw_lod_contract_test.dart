import 'package:test/test.dart';
import 'package:vrlizate_world/vrlizate_world.dart';

import 'vrlw_bundle_test.dart' as bundle;
import 'vrlw_resources_test.dart' as resources;

Map<String, Object?> _binding(Map<String, Object?> source) =>
    (source['prototypeBindings'] as List).first as Map<String, Object?>;

Map<String, Object?> _source() {
  final source = resources.resourceSource();
  _binding(source)['lods'] = [
    {'node': 'lod0', 'minDistanceMeters': 0},
    {'node': 'lod1', 'minDistanceMeters': 18},
    {'node': 'lod2', 'minDistanceMeters': 42},
  ];
  return source;
}

void _rejectBoth(void Function(Map<String, Object?>) mutate) {
  final source = _source();
  mutate(source);
  expect(() => VrlwBundleCodec.encode(source), throwsFormatException);
  final baseline = VrlwBundleCodec.encode(_source());
  final index = bundle.indexOf(baseline);
  final document = bundle.indexJson(baseline);
  mutate(document);
  expect(
    () => bundle.indexOf(
      bundle.makeBundle(document, baseline.sublist(index.header.payloadOffset)),
    ),
    throwsFormatException,
  );
}

void main() {
  for (final compressed in [false, true]) {
    test(
      'LOD roots and thresholds survive bounded v1 roundtrip ($compressed)',
      () {
        final source = _source();
        final index = bundle.indexOf(
          VrlwBundleCodec.encode(source, compress: compressed),
        );
        final binding = index.prototypeBindings.single;
        expect(binding.lods.map((level) => level.node), [
          'lod0',
          'lod1',
          'lod2',
        ]);
        expect(binding.lods.map((level) => level.minDistanceMeters), [
          0,
          18,
          42,
        ]);
        expect(binding.lodHysteresisMeters, 2);
        expect(binding.toJson()['lodHysteresisMeters'], 2);
        expect(binding.toJson()['lods'], _binding(source)['lods']);
        expect(() => binding.lods.clear(), throwsUnsupportedError);
      },
    );
  }

  test('two levels and custom bounded hysteresis are supported', () {
    final source = _source();
    (_binding(source)['lods'] as List).removeLast();
    _binding(source)['lodHysteresisMeters'] = .5;
    final binding = bundle
        .indexOf(VrlwBundleCodec.encode(source))
        .prototypeBindings
        .single;
    expect(binding.lods.length, 2);
    expect(binding.lodHysteresisMeters, .5);
  });

  test('legacy bindings keep their serialized shape and no LOD', () {
    final source = resources.resourceSource();
    final binding = bundle
        .indexOf(VrlwBundleCodec.encode(source))
        .prototypeBindings
        .single;
    expect(binding.lods, isEmpty);
    expect(binding.toJson(), _binding(source));
  });

  final invalid = <String, void Function(Map<String, Object?>)>{
    'missing levels with hysteresis': (s) {
      _binding(s).remove('lods');
      _binding(s)['lodHysteresisMeters'] = 2;
    },
    'empty levels': (s) => _binding(s)['lods'] = [],
    'single level': (s) => _binding(s)['lods'] = [
      {'node': 'lod0', 'minDistanceMeters': 0},
    ],
    'four levels': (s) => (_binding(s)['lods'] as List).add({
      'node': 'lod3',
      'minDistanceMeters': 80,
    }),
    'duplicate root names': (s) =>
        ((_binding(s)['lods'] as List)[1] as Map)['node'] = 'lod0',
    'invalid root name': (s) =>
        ((_binding(s)['lods'] as List)[1] as Map)['node'] = '../node',
    'first threshold not zero': (s) =>
        ((_binding(s)['lods'] as List)[0] as Map)['minDistanceMeters'] = 1,
    'negative threshold': (s) =>
        ((_binding(s)['lods'] as List)[1] as Map)['minDistanceMeters'] = -1,
    'descending threshold': (s) =>
        ((_binding(s)['lods'] as List)[2] as Map)['minDistanceMeters'] = 10,
    'overlapping hysteresis bands': (s) =>
        ((_binding(s)['lods'] as List)[1] as Map)['minDistanceMeters'] = 4,
    'unbounded threshold': (s) =>
        ((_binding(s)['lods'] as List)[2] as Map)['minDistanceMeters'] = 1025,
    'missing threshold': (s) =>
        ((_binding(s)['lods'] as List)[1] as Map).remove('minDistanceMeters'),
    'unknown level field': (s) =>
        ((_binding(s)['lods'] as List)[1] as Map)['script'] = 'run.dart',
    'zero hysteresis': (s) => _binding(s)['lodHysteresisMeters'] = 0,
    'negative hysteresis': (s) => _binding(s)['lodHysteresisMeters'] = -1,
    'unbounded hysteresis': (s) => _binding(s)['lodHysteresisMeters'] = 17,
    'null hysteresis': (s) => _binding(s)['lodHysteresisMeters'] = null,
    'moving LOD prototype': (s) => s['motions'] = [
      {
        'id': 'spin',
        'prototypeId': 'tree',
        'node': 'lod0',
        'kind': 'spin',
        'axis': 'y',
        'periodSeconds': 12,
      },
    ],
  };
  for (final entry in invalid.entries) {
    test(
      'source and downloaded index reject ${entry.key}',
      () => _rejectBoth(entry.value),
    );
  }

  test('non-finite authoring thresholds are rejected', () {
    for (final bad in [double.nan, double.infinity, double.negativeInfinity]) {
      final source = _source();
      ((_binding(source)['lods'] as List)[1] as Map)['minDistanceMeters'] = bad;
      expect(() => VrlwBundleCodec.encode(source), throwsFormatException);
    }
  });
}
