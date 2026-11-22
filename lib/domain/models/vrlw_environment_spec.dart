import 'vrlw_day_night_cycle_spec.dart';

/// World-level lighting, IBL/skybox, exposure, atmospheric height-fog,
/// animated water surface policy, and directional sun parameters.
final class VrlwEnvironmentSpec {
  const VrlwEnvironmentSpec({
    this.environmentResource,
    this.skyboxResource,
    this.environmentIntensity,
    this.exposure,
    this.sunDirection,
    this.sunColor,
    this.sunIntensity,
    this.castsShadows,
    this.dayNightCycle,
    this.fogColor,
    this.fogDensity,
    this.fogMaxOpacity,
    this.fogHeightFalloff,
    this.fogCutoffDistance,
    this.fogSkyColorInfluence,
    this.fogSunInScatter,
    this.animatedWater,
  });

  final String? environmentResource;
  final String? skyboxResource;
  final double? environmentIntensity;
  final double? exposure;
  final List<double>? sunDirection;
  final List<double>? sunColor;
  final double? sunIntensity;
  final bool? castsShadows;
  final VrlwDayNightCycleSpec? dayNightCycle;

  /// Optional linear RGB `[r, g, b]` (`0..1`) atmospheric fog color.
  final List<double>? fogColor;

  /// Optional exponential fog density (`0..0.2`; `0` disables atmospheric fog).
  final double? fogDensity;

  /// Optional maximum fog opacity (`0..1`) so distant silhouettes never dissolve.
  final double? fogMaxOpacity;

  /// Optional vertical mist falloff (`0..2`) concentrating haze near valleys/water.
  final double? fogHeightFalloff;

  /// Optional distance cutoff (`10..5000 m`) beyond which sky/stars stay crisp.
  final double? fogCutoffDistance;

  /// Optional sky-horizon tint blending factor (`0..1`) into atmospheric fog.
  final double? fogSkyColorInfluence;

  /// Optional directional sun in-scattering factor (`0..1`) for golden dusk/dawn glow.
  final double? fogSunInScatter;

  /// Optional flag enabling zero-allocation GPU normal-map ripple animation on
  /// water prototypes/surfaces (`null` defaults to host runtime policy).
  final bool? animatedWater;

  Map<String, Object> toJson() => {
    if (environmentResource != null)
      'environmentResource': environmentResource!,
    if (skyboxResource != null) 'skyboxResource': skyboxResource!,
    if (environmentIntensity != null)
      'environmentIntensity': environmentIntensity!,
    if (exposure != null) 'exposure': exposure!,
    if (sunDirection != null) 'sunDirection': sunDirection!,
    if (sunColor != null) 'sunColor': sunColor!,
    if (sunIntensity != null) 'sunIntensity': sunIntensity!,
    if (castsShadows != null) 'castsShadows': castsShadows!,
    if (dayNightCycle != null) 'dayNightCycle': dayNightCycle!.toJson(),
    if (fogColor != null) 'fogColor': fogColor!,
    if (fogDensity != null) 'fogDensity': fogDensity!,
    if (fogMaxOpacity != null) 'fogMaxOpacity': fogMaxOpacity!,
    if (fogHeightFalloff != null) 'fogHeightFalloff': fogHeightFalloff!,
    if (fogCutoffDistance != null) 'fogCutoffDistance': fogCutoffDistance!,
    if (fogSkyColorInfluence != null)
      'fogSkyColorInfluence': fogSkyColorInfluence!,
    if (fogSunInScatter != null) 'fogSunInScatter': fogSunInScatter!,
    if (animatedWater != null) 'animatedWater': animatedWater!,
  };
}
