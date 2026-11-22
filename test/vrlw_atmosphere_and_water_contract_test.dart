import 'package:test/test.dart';
import 'package:vrlizate_world/vrlizate_world.dart';

import 'vrlw_bundle_test.dart' as bundle;
import 'vrlw_resources_test.dart' as resources;

Map<String, Object?> _sourceWithAtmosphere() => resources.resourceSource()
  ..['environment'] = <String, Object?>{
    'sunDirection': [0.3, -0.9, -0.4],
    'sunColor': [1.0, 0.91, 0.8],
    'sunIntensity': 2.2,
    'fogColor': [0.14, 0.23, 0.36],
    'fogDensity': 0.009,
    'fogMaxOpacity': 0.78,
    'fogHeightFalloff': 0.05,
    'fogCutoffDistance': 330.0,
    'fogSkyColorInfluence': 0.28,
    'fogSunInScatter': 0.22,
    'animatedWater': true,
  };

void main() {
  test('VrlwEnvironmentSpec roundtrips atmospheric height-fog and animatedWater', () {
    final bytes = VrlwBundleCodec.encode(_sourceWithAtmosphere());
    final index = bundle.indexOf(bytes);
    final env = index.environment!;

    expect(env.fogColor, [0.14, 0.23, 0.36]);
    expect(env.fogDensity, closeTo(0.009, 1e-9));
    expect(env.fogMaxOpacity, closeTo(0.78, 1e-9));
    expect(env.fogHeightFalloff, closeTo(0.05, 1e-9));
    expect(env.fogCutoffDistance, closeTo(330.0, 1e-9));
    expect(env.fogSkyColorInfluence, closeTo(0.28, 1e-9));
    expect(env.fogSunInScatter, closeTo(0.22, 1e-9));
    expect(env.animatedWater, isTrue);

    // Omitting new fields keeps JSON serialization backward-compatible.
    const minimal = VrlwEnvironmentSpec(exposure: 1.0);
    expect(minimal.toJson().containsKey('fogDensity'), isFalse);
    expect(minimal.toJson().containsKey('animatedWater'), isFalse);
  });

  test('VrlwBundleCodec rejects out-of-range fog parameters and non-bool animatedWater', () {
    for (final mutate in <void Function(Map<String, Object?>)>[
      (env) => env['fogDensity'] = -0.01,
      (env) => env['fogDensity'] = 0.5,
      (env) => env['fogMaxOpacity'] = 1.5,
      (env) => env['fogHeightFalloff'] = 3.0,
      (env) => env['fogCutoffDistance'] = 5.0,
      (env) => env['fogSkyColorInfluence'] = -0.1,
      (env) => env['fogSunInScatter'] = 1.2,
      (env) => env['fogColor'] = [0.5, 0.5],
      (env) => env['fogColor'] = [1.5, 0.5, 0.5],
      (env) => env['animatedWater'] = 'yes',
    ]) {
      final doc = _sourceWithAtmosphere();
      mutate(doc['environment']! as Map<String, Object?>);
      expect(() => VrlwBundleCodec.encode(doc), throwsFormatException);
    }
  });
}
