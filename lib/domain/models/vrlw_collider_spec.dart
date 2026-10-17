/// Bounding collision primitive declared for a prototype in a `.vrlw` bundle.
final class VrlwColliderSpec {
  const VrlwColliderSpec({
    required this.shape,
    this.halfExtents,
    this.radius,
    this.height,
    this.offset = const [0, 0, 0],
  });

  /// One of `'box'`, `'sphere'`, `'cylinder'`, or `'capsule'`.
  final String shape;

  /// Half-extents `[hx, hy, hz]` in meters when [shape] is `'box'`.
  final List<double>? halfExtents;

  /// Radius in meters when [shape] is `'sphere'`, `'cylinder'`, or `'capsule'`.
  final double? radius;

  /// Total height in meters when [shape] is `'cylinder'` or `'capsule'`.
  final double? height;

  /// Local center offset `[x, y, z]` in meters relative to prototype origin.
  final List<double> offset;

  Map<String, Object> toJson() => {
    'shape': shape,
    if (halfExtents != null) 'halfExtents': halfExtents!,
    if (radius != null) 'radius': radius!,
    if (height != null) 'height': height!,
    if (offset[0] != 0 || offset[1] != 0 || offset[2] != 0) 'offset': offset,
  };
}
