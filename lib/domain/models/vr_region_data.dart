import '../../utils/constants/vr_world_constants.dart';

/// Resident decoded data, independent of meshes, textures, or active rendering.
///
/// [sizeBytes] must conservatively account for decoded resident memory, not just
/// compressed transfer size. Hosts own actual resource measurement and release.
final class VrRegionData<T> {
  VrRegionData({required this.value, required this.sizeBytes}) {
    if (sizeBytes < 0 || sizeBytes > VrWorldConstants.maxRegionDataBytes) {
      throw ArgumentError.value(sizeBytes, VrWorldConstants.paramSizeBytes);
    }
  }

  final T value;
  final int sizeBytes;
}
