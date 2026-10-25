/// A nearby, explicit host action with visit-local state and no downloaded code.
final class VrlwInteractionSpec {
  VrlwInteractionSpec({
    required this.id,
    required this.label,
    required List<double> position,
    required this.action,
    required this.target,
    this.maxDistance = 3,
  }) : position = List.unmodifiable(position);

  final String id, label;

  /// World-local, Y-up meters; X/Z must lie in an indexed region.
  final List<double> position;
  final double maxDistance;

  /// `toggleMotion` targets a motion ID; `toggleAudio` targets an emitter ID.
  final String action;
  final String target;

  Map<String, Object> toJson() => {
    'id': id,
    'label': label,
    'position': position,
    'maxDistance': maxDistance,
    'action': action,
    'target': target,
  };
}
