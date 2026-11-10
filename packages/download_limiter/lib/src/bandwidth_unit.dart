/// Bandwidth units a limit can be expressed in (§10).
enum BandwidthUnit {
  bytesPerSecond,
  kibibytesPerSecond,
  mebibytesPerSecond;

  int toBytesPerSecond(num value) {
    switch (this) {
      case BandwidthUnit.bytesPerSecond:
        return value.round();
      case BandwidthUnit.kibibytesPerSecond:
        return (value * 1024).round();
      case BandwidthUnit.mebibytesPerSecond:
        return (value * 1024 * 1024).round();
    }
  }
}
