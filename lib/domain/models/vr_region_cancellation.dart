import 'vr_region_load_cancelled.dart';

/// Cooperative cancellation. Providers should cancel their own network request
/// when possible. Ignored cancellation still discards the eventual result.
final class VrRegionCancellation {
  bool _isCancelled = false;
  bool get isCancelled => _isCancelled;

  void cancel() {
    _isCancelled = true;
  }

  void throwIfCancelled() {
    if (_isCancelled) throw const VrRegionLoadCancelled();
  }
}
