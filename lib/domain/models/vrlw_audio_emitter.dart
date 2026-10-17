/// Positional spatial audio emitter bound to a packaged `audio.*` resource.
final class VrlwAudioEmitter {
  const VrlwAudioEmitter({
    required this.id,
    required this.resource,
    required this.x,
    required this.y,
    required this.z,
    this.volume = 1.0,
    this.maxDistance = 24.0,
    this.loop = true,
  });

  final String id;
  final String resource;
  final double x, y, z;
  final double volume;
  final double maxDistance;
  final bool loop;

  Map<String, Object> toJson() => {
    'id': id,
    'resource': resource,
    'x': x,
    'y': y,
    'z': z,
    'volume': volume,
    'maxDistance': maxDistance,
    'loop': loop,
  };
}
