import 'constants/vr_world_constants.dart';

abstract final class VrWorldValidator {
  static final RegExp _identifier = RegExp(VrWorldConstants.identifierPattern);

  /// Shared validation for explicit identifiers; deliberately not a URL/path.
  static void validateIdentifier(String value, String name) {
    if (_identifier.firstMatch(value)?.end != value.length || value.isEmpty) {
      throw ArgumentError.value(
        value,
        name,
        VrWorldConstants.errInvalidIdentifier,
      );
    }
  }

  /// Shared source bounds. Zero-length reads are intentionally unsupported.
  static void validateRange(int offset, int length, {int? totalLength}) {
    final maximum = totalLength ?? VrWorldConstants.vrlwMaxFileBytes;
    if (offset < 0 ||
        length <= 0 ||
        length > VrWorldConstants.vrlwMaxReadLength ||
        offset > maximum - length) {
      throw RangeError(VrWorldConstants.errVrlwRangeBudget);
    }
  }
}
