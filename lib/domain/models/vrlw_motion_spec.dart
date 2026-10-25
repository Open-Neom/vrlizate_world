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
  }) : pivot = List.unmodifiable(pivot);

  final String id, prototypeId, node;

  /// `spin` completes one turn per period; `bob` follows one sine period.
  final String kind;

  /// Model-local axis: `x`, `y`, or `z`.
  final String axis;
  final List<double> pivot;
  final double periodSeconds;

  /// Model-local displacement in meters, present only for `bob`.
  final double? amplitude;
  final double rangeMeters;
  final bool initiallyEnabled;

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
  };
}
