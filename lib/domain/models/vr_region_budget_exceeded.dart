import 'vr_region_key.dart';

final class VrRegionBudgetExceeded implements Exception {
  const VrRegionBudgetExceeded(this.key, this.sizeBytes);

  final VrRegionKey key;
  final int sizeBytes;

  @override
  String toString() => 'Region $key ($sizeBytes bytes) exceeds cache capacity.';
}
