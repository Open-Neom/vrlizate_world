/// Bounded, host-evaluated motion of one named GLB mesh node.
///
/// This is data, not an executable animation or permission to move colliders.
/// The host must validate the target node and cap resident animated instances.
final class VrlwMotionSpec {
  VrlwMotionSpec({
    required this.id,
    required this.prototypeId,
    required this.node,
    required this.kind,
    required this.axis,
    required this.periodSeconds,
    List<double> pivot = const [0, 0, 0],
    this.amplitude,
    this.rangeMeters = 32,
    this.initiallyEnabled = true,
    List<List<double>> waypoints = const [],
    this.phaseOffset = 0,
    this.orientToPath = true,
  }) : pivot = List.unmodifiable(pivot),
       waypoints = List.unmodifiable(
         waypoints.map((point) => List<double>.unmodifiable(point)),
       );

  final String id, prototypeId, node;

  /// `spin` completes one turn, `bob` one sine period, and `path` one closed lap.
  final String kind;

  /// Model-local axis: `x`, `y`, or `z`.
  final String axis;
  final List<double> pivot;
  final double periodSeconds;

  /// Model-local displacement in meters, present only for `bob`.
  final double? amplitude;
  final double rangeMeters;
  final bool initiallyEnabled;

  /// Model-local closed circuit; the last point must not repeat the first.
  /// Empty for legacy `spin`/`bob`. Every nested vector is immutable.
  final List<List<double>> waypoints;

  /// Normalized starting lap phase, in [0, 1); used only by `path`.
  final double phaseOffset;

  /// Whether the host turns a path mesh toward the segment heading.
  final bool orientToPath;

  Map<String, Object> toJson() => {
    'id': id,
    'prototypeId': prototypeId,
    'node': node,
    'kind': kind,
    'axis': axis,
    'pivot': pivot,
    'periodSeconds': periodSeconds,
    if (amplitude != null) 'amplitude': amplitude!,
    'rangeMeters': rangeMeters,
    'initiallyEnabled': initiallyEnabled,
    if (kind == 'path') ...{
      'waypoints': waypoints,
      'phaseOffset': phaseOffset,
      'orientToPath': orientToPath,
    },
  };
}
