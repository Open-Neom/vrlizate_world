/// One static detail level in the same GLB as its prototype binding.
///
/// [node] identifies a root in the active GLB scene. The mobile profile checks
/// the complete node trees before importing them. Distances are world meters
/// from the transformed LOD0 bounds, not an eye-specific screen projection.
final class VrlwLodLevel {
  const VrlwLodLevel({required this.node, required this.minDistanceMeters});

  final String node;
  final double minDistanceMeters;

  Map<String, Object> toJson() => {
    'node': node,
    'minDistanceMeters': minDistanceMeters,
  };
}
