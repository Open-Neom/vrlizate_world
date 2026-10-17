import 'vr_region_data.dart';
import 'vr_region_key.dart';

final class VrRegionSnapshot<T> {
  VrRegionSnapshot({
    required this.current,
    required Map<VrRegionKey, VrRegionData<T>> resident,
    required Set<VrRegionKey> demanded,
    required this.residentBytes,
    required this.inFlightLoads,
    required Map<VrRegionKey, Object> errors,
  }) : resident = Map.unmodifiable(resident),
       demanded = Set.unmodifiable(demanded),
       errors = Map.unmodifiable(errors);

  final VrRegionKey? current;
  final Map<VrRegionKey, VrRegionData<T>> resident;
  final Set<VrRegionKey> demanded;
  final int residentBytes;
  final int inFlightLoads;
  final Map<VrRegionKey, Object> errors;

  VrRegionData<T>? get currentData => resident[current];
}
