import '../utils/vr_world_validator.dart';

export '../domain/models/vr_world_address.dart';
export '../utils/vr_world_validator.dart';

/// Shared validation for explicit identifiers; deliberately not a URL/path.
void validateWorldIdentifier(String value, String name) =>
    VrWorldValidator.validateIdentifier(value, name);
