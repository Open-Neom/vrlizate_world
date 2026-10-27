/// Host-evaluated visual day/night cycle; not a wall clock or weather simulator.
final class VrlwDayNightCycleSpec {
  const VrlwDayNightCycleSpec({
    required this.durationSeconds,
    this.initialHour = 12,
  });

  /// Seconds for one complete virtual 24-hour day.
  final double durationSeconds;

  /// Initial visual hour in [0, 24), unrelated to real-world time zones.
  final double initialHour;

  Map<String, Object> toJson() => {
    'durationSeconds': durationSeconds,
    'initialHour': initialHour,
  };
}
