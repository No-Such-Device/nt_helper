/// A device-reported memory pool measurement.
///
/// [free] is the direct difference between the reported total and current
/// values. It is intentionally not clamped: a negative value preserves an
/// inconsistent device reading instead of fabricating a larger capacity.
final class MemoryPoolUsage {
  const MemoryPoolUsage({required this.total, required this.current});

  final int total;
  final int current;

  int get free => total - current;
}

/// Device-reported memory usage for the four disting NT memory pools.
final class MemoryUsage {
  const MemoryUsage({
    required this.sram,
    required this.dram,
    required this.dtc,
    required this.itc,
  });

  final MemoryPoolUsage sram;
  final MemoryPoolUsage dram;
  final MemoryPoolUsage dtc;
  final MemoryPoolUsage itc;
}
