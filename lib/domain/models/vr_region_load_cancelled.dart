import '../../utils/constants/vr_world_constants.dart';

final class VrRegionLoadCancelled implements Exception {
  const VrRegionLoadCancelled();

  @override
  String toString() => VrWorldConstants.errRegionCancelled;
}
