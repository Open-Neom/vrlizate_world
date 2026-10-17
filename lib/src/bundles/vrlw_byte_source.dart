import '../../utils/vr_world_validator.dart';

export '../../domain/models/vrlw_byte_source.dart';
export '../../domain/services/vrlw_memory_source.dart';

/// Shared source bounds. Zero-length reads are intentionally unsupported.
void validateVrlwRange(int offset, int length, {int? totalLength}) =>
    VrWorldValidator.validateRange(offset, length, totalLength: totalLength);
