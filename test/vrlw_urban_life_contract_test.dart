import 'package:crypto/crypto.dart';
import 'package:test/test.dart';
import 'package:vrlizate_world/vrlizate_world.dart';

import 'vrlw_bundle_test.dart' as bundle;
import 'vrlw_resources_test.dart' as resources;

Map<String, Object?> _path({
  String id = 'pedestrian',
  String node = 'person',
}) => {
  'id': id,
  'prototypeId': 'tree',
  'node': node,
  'kind': 'path',
  'axis': 'y',
  'periodSeconds': 18,
  'waypoints': [
    [0, 0, 0],
    [4, 0, 0],
    [4, 0, -3],
  ],
};

Map<String, Object?> _source() => resources.resourceSource()
  ..['motions'] = [_path()]
  ..['environment'] = <String, Object?>{
    'sunDirection': [-.4, -1, -.2],
    'sunIntensity': 2.5,
    'dayNightCycle': <String, Object?>{'durationSeconds': 600},
  };

/// Golden input also exercised against the prior committed codec, before these
/// fields existed. A new optional field must not rewrite existing packages.
Map<String, Object?> legacyUrbanSource() => resources.resourceSource()
  ..['motions'] = [
    {
      'id': 'rotor',
      'prototypeId': 'tree',
      'node': 'rotor-node',
      'kind': 'spin',
      'axis': 'y',
      'periodSeconds': 12,
    },
    {
      'id': 'beacon',
      'prototypeId': 'tree',
      'node': 'beacon-node',
      'kind': 'bob',
      'axis': 'z',
      'periodSeconds': 8,
      'amplitude': .2,
    },
  ]
  ..['environment'] = <String, Object?>{
    'sunDirection': [-.4, -1, -.2],
    'sunIntensity': 2.5,
    'exposure': 1.1,
  };

Map<String, Object?> _motion(Map<String, Object?> document) =>
    (document['motions'] as List).first as Map<String, Object?>;

Map<String, Object?> _cycle(Map<String, Object?> document) =>
    (document['environment'] as Map<String, Object?>)['dayNightCycle']
        as Map<String, Object?>;

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
    test('path and visual cycle roundtrip with defaults ($compress)', () {
      final bytes = VrlwBundleCodec.encode(_source(), compress: compress);
      final index = bundle.indexOf(bytes);
      final path = index.motions.single;
      expect(path.kind, 'path');
      expect(path.axis, 'y');
      expect(path.pivot, [0, 0, 0]);
      expect(path.waypoints, [
        [0, 0, 0],
        [4, 0, 0],
        [4, 0, -3],
      ]);
      expect(path.phaseOffset, 0);
      expect(path.orientToPath, isTrue);
      expect(path.amplitude, isNull);
      final cycle = index.environment!.dayNightCycle!;
      expect(cycle.durationSeconds, 600);
      expect(cycle.initialHour, 12);
      expect(bundle.indexJson(bytes)['schemaVersion'], 1);
      expect(String.fromCharCodes(bytes.sublist(0, 8)), 'VRLW0001');
      expect(() => path.waypoints.clear(), throwsUnsupportedError);
      expect(() => path.waypoints[0][0] = 2, throwsUnsupportedError);
    });
  }

  test(
    'upper waypoint limit, offset, orientation and cycle boundaries survive',
    () {
      final source = _source();
      _motion(source).addAll({
        'waypoints': List.generate(16, (i) => [i.toDouble() - 8, 0, 0]),
        'phaseOffset': .999999,
        'orientToPath': false,
        'periodSeconds': 120,
      });
      _cycle(source).addAll({'durationSeconds': 7200, 'initialHour': 23.99999});
      final index = bundle.indexOf(VrlwBundleCodec.encode(source));
      expect(index.motions.single.waypoints, hasLength(16));
      expect(index.motions.single.phaseOffset, .999999);
      expect(index.motions.single.orientToPath, isFalse);
      expect(index.environment!.dayNightCycle!.initialHour, 23.99999);
      expect(index.environment!.dayNightCycle!.durationSeconds, 7200);
    },
  );

  test(
    'zero hour, minimum duration and full coordinate boundaries are accepted',
    () {
      final source = _source();
      _motion(source)['waypoints'] = [
        [-32, -32, -32],
        [32, 32, 32],
        [0, 0, 0],
      ];
      _cycle(source).addAll({'durationSeconds': 120, 'initialHour': 0});
      final index = bundle.indexOf(VrlwBundleCodec.encode(source));
      expect(index.motions.single.waypoints.first, [-32, -32, -32]);
      expect(index.environment!.dayNightCycle!.initialHour, 0);
    },
  );

  test(
    'constructor copies every path vector and only paths emit their fields',
    () {
      final points = <List<double>>[
        [0, 0, 0],
        [1, 0, 0],
        [1, 0, 1],
      ];
      final path = VrlwMotionSpec(
        id: 'person',
        prototypeId: 'tree',
        node: 'person',
        kind: 'path',
        axis: 'y',
        periodSeconds: 30,
        waypoints: points,
      );
      points[0][0] = 9;
      points.add([2, 0, 2]);
      expect(path.waypoints, [
        [0, 0, 0],
        [1, 0, 0],
        [1, 0, 1],
      ]);
      expect(path.toJson()['phaseOffset'], 0);
      expect(path.toJson()['orientToPath'], isTrue);
      final legacy = VrlwMotionSpec(
        id: 'rotor',
        prototypeId: 'tree',
        node: 'rotor',
        kind: 'spin',
        axis: 'y',
        periodSeconds: 12,
      );
      expect(legacy.waypoints, isEmpty);
      expect(legacy.toJson().containsKey('waypoints'), isFalse);
      expect(legacy.toJson().containsKey('phaseOffset'), isFalse);
      expect(legacy.toJson().containsKey('orientToPath'), isFalse);
      expect(
        const VrlwEnvironmentSpec().toJson().containsKey('dayNightCycle'),
        isFalse,
      );
      expect(const VrlwDayNightCycleSpec(durationSeconds: 600).toJson(), {
        'durationSeconds': 600.0,
        'initialHour': 12.0,
      });
    },
  );

  test('eight path tracks remain the limit across distinct nodes', () {
    final source = _source()
      ..['motions'] = List.generate(
        8,
        (i) => _path(id: 'person-$i', node: 'person-$i'),
      );
    expect(
      bundle.indexOf(VrlwBundleCodec.encode(source)).motions,
      hasLength(8),
    );
    (source['motions'] as List).add(_path(id: 'person-9', node: 'person-9'));
    expect(() => VrlwBundleCodec.encode(source), throwsFormatException);
  });

  final invalid = <String, void Function(Map<String, Object?>)>{
    'missing waypoints': (d) => _motion(d).remove('waypoints'),
    'null waypoints': (d) => _motion(d)['waypoints'] = null,
    'nonlist waypoints': (d) => _motion(d)['waypoints'] = 'circle',
    'two waypoints': (d) => _motion(d)['waypoints'] = [
      [0, 0, 0],
      [1, 0, 0],
    ],
    'seventeen waypoints': (d) =>
        _motion(d)['waypoints'] = List.generate(17, (i) => [i, 0, 0]),
    'point with two coordinates': (d) => _motion(d)['waypoints'] = [
      [0, 0],
      [1, 0, 0],
      [1, 0, 1],
    ],
    'point is not vector': (d) => _motion(d)['waypoints'] = [
      0,
      [1, 0, 0],
      [1, 0, 1],
    ],
    'point too positive': (d) => _motion(d)['waypoints'] = [
      [32.001, 0, 0],
      [1, 0, 0],
      [1, 0, 1],
    ],
    'point too negative': (d) => _motion(d)['waypoints'] = [
      [0, -32.001, 0],
      [1, 0, 0],
      [1, 0, 1],
    ],
    'duplicate consecutive point': (d) => _motion(d)['waypoints'] = [
      [0, 0, 0],
      [0, 0, 0],
      [1, 0, 1],
    ],
    'explicit duplicated closing point': (d) => _motion(d)['waypoints'] = [
      [0, 0, 0],
      [1, 0, 0],
      [0, 0, 0],
    ],
    'horizontal axis other than y': (d) => _motion(d)['axis'] = 'x',
    'nonzero pivot': (d) => _motion(d)['pivot'] = [0, .001, 0],
    'path amplitude': (d) => _motion(d)['amplitude'] = .1,
    'negative phase': (d) => _motion(d)['phaseOffset'] = -.001,
    'phase reaches one': (d) => _motion(d)['phaseOffset'] = 1,
    'null phase': (d) => _motion(d)['phaseOffset'] = null,
    'orientation nonboolean': (d) => _motion(d)['orientToPath'] = 1,
    'orientation null': (d) => _motion(d)['orientToPath'] = null,
    'path-only points on spin': (d) => _motion(d)['kind'] = 'spin',
    'path-only phase on bob': (d) =>
        _motion(d).addAll({'kind': 'bob', 'amplitude': .1, 'phaseOffset': 0}),
    'unknown path command': (d) => _motion(d)['onArrival'] = 'run()',
    'missing cycle duration': (d) => _cycle(d).remove('durationSeconds'),
    'cycle is null': (d) => (d['environment'] as Map)['dayNightCycle'] = null,
    'cycle is list': (d) => (d['environment'] as Map)['dayNightCycle'] = [],
    'short cycle': (d) => _cycle(d)['durationSeconds'] = 119.999,
    'long cycle': (d) => _cycle(d)['durationSeconds'] = 7200.001,
    'duration is string': (d) => _cycle(d)['durationSeconds'] = '600',
    'negative hour': (d) => _cycle(d)['initialHour'] = -.001,
    'hour reaches 24': (d) => _cycle(d)['initialHour'] = 24,
    'null hour': (d) => _cycle(d)['initialHour'] = null,
    'unhandled cycle field': (d) => _cycle(d)['weather'] = 'rain',
    'day cycle outside environment': (d) =>
        d['dayNightCycle'] = {'durationSeconds': 600},
  };
  for (final entry in invalid.entries) {
    test(
      'strict writer/reader reject ${entry.key}',
      () => _rejectBoth(entry.value),
    );
  }

  for (final kind in ['spin', 'bob']) {
    for (final field in ['waypoints', 'phaseOffset', 'orientToPath']) {
      test('$kind rejects isolated path-only $field in writer and reader', () {
        _rejectBoth((document) {
          final motion = _motion(document);
          motion.remove('waypoints');
          motion['kind'] = kind;
          if (kind == 'bob') motion['amplitude'] = .1;
          motion[field] = switch (field) {
            'waypoints' => [
              [0, 0, 0],
              [1, 0, 0],
              [1, 0, 1],
            ],
            'phaseOffset' => 0,
            _ => true,
          };
        });
      });
    }
  }

  test(
    'nonfinite route, phase, hour and duration are rejected before JSON',
    () {
      for (final value in [
        double.nan,
        double.infinity,
        double.negativeInfinity,
      ]) {
        for (final mutate in <void Function(Map<String, Object?>)>[
          (d) => _motion(d)['waypoints'] = [
            [value, 0, 0],
            [1, 0, 0],
            [1, 0, 1],
          ],
          (d) => _motion(d)['phaseOffset'] = value,
          (d) => _cycle(d)['initialHour'] = value,
          (d) => _cycle(d)['durationSeconds'] = value,
        ]) {
          final source = _source();
          mutate(source);
          expect(() => VrlwBundleCodec.encode(source), throwsFormatException);
        }
      }
    },
  );

  test('legacy spin, bob and environment keep their committed byte hashes', () {
    // Filled from the preceding committed codec, not from the implementation
    // under test. Both representations retain their exact canonical bytes.
    const expected = <bool, String>{
      false: '25442624cece986f784cc32f3147c441a9e586c1723b6d8a3d8a64239d4c1415',
      true: 'c8bd1f7d939ca427de937438c61c103a8678933455a8648846a828d3aebde091',
    };
    for (final entry in expected.entries) {
      final bytes = VrlwBundleCodec.encode(
        legacyUrbanSource(),
        compress: entry.key,
      );
      expect(sha256.convert(bytes).toString(), entry.value);
      final index = bundle.indexOf(bytes);
      expect(index.environment!.dayNightCycle, isNull);
      expect(index.motions.every((m) => m.waypoints.isEmpty), isTrue);
    }
  });
}
