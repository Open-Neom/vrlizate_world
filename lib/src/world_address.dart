/// One independently populated instance of a world.
///
/// Two visitors share a coordinate space only when BOTH IDs match. IDs are
/// opaque stable identifiers, never physical GPS coordinates or user identity.
final class VrWorldAddress {
  factory VrWorldAddress({
    required String worldId,
    required String instanceId,
  }) {
    validateWorldIdentifier(worldId, 'worldId');
    validateWorldIdentifier(instanceId, 'instanceId');
    return VrWorldAddress._(worldId, instanceId);
  }

  const VrWorldAddress._(this.worldId, this.instanceId);

  final String worldId;
  final String instanceId;

  @override
  bool operator ==(Object other) =>
      other is VrWorldAddress &&
      worldId == other.worldId &&
      instanceId == other.instanceId;

  @override
  int get hashCode => Object.hash(worldId, instanceId);

  @override
  String toString() => '$worldId@$instanceId';
}

final _identifier = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$');

/// Shared validation for explicit identifiers; deliberately not a URL/path.
void validateWorldIdentifier(String value, String name) {
  if (_identifier.firstMatch(value)?.end != value.length || value.isEmpty) {
    throw ArgumentError.value(
      value,
      name,
      'Expected 1–128 ASCII letters/digits/dot/underscore/colon/hyphen, '
      'starting with a letter or digit.',
    );
  }
}
