/// World-level lighting, IBL/skybox, exposure, and directional sun parameters.
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
  });

  final String? environmentResource;
  final String? skyboxResource;
  final double? environmentIntensity;
  final double? exposure;
  final List<double>? sunDirection;
  final List<double>? sunColor;
  final double? sunIntensity;
  final bool? castsShadows;

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
  };
}
