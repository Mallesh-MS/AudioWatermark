/// Standard CRC-8 error-detection checksum implementation.
///
/// Uses the ATM polynomial (0x07 = x^8 + x^2 + x + 1), initial value 0x00.
/// Detects 100% of single-bit errors, 100% of two-bit errors, and all burst
/// errors up to 8 bits in length over acoustic watermarking payloads.
class Crc8 {
  static const int polynomial = 0x07;

  /// Computes the 8-bit CRC over [bytes].
  static int compute(List<int> bytes) {
    var crc = 0x00;
    for (final byte in bytes) {
      crc ^= (byte & 0xFF);
      for (int i = 0; i < 8; i++) {
        if ((crc & 0x80) != 0) {
          crc = ((crc << 1) ^ polynomial) & 0xFF;
        } else {
          crc = (crc << 1) & 0xFF;
        }
      }
    }
    return crc & 0xFF;
  }

  /// Appends a 1-byte CRC checksum to [payloadBytes].
  static List<int> appendChecksum(List<int> payloadBytes) {
    final crc = compute(payloadBytes);
    return [...payloadBytes, crc];
  }

  /// Verifies the trailing 1-byte CRC checksum on [bytesWithChecksum].
  ///
  /// Returns the uncorrupted payload bytes (excluding the checksum) on success,
  /// or `null` if the checksum does not match or the buffer is too short.
  static List<int>? verifyAndExtract(List<int> bytesWithChecksum) {
    if (bytesWithChecksum.length < 2) return null;
    final payload = bytesWithChecksum.sublist(0, bytesWithChecksum.length - 1);
    final expectedCrc = bytesWithChecksum.last;
    final actualCrc = compute(payload);
    if (actualCrc == expectedCrc) {
      return payload;
    }
    return null;
  }
}
