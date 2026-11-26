/// 通用格式化工具。
class Fmt {
  const Fmt._();

  static String uptime(int seconds) {
    if (seconds <= 0) return '—';
    final days = seconds ~/ 86400;
    final hours = (seconds % 86400) ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final sb = StringBuffer();
    if (days > 0) sb.write('$days天');
    if (hours > 0 || days > 0) sb.write('$hours时');
    sb.write('$minutes分');
    return sb.toString();
  }

  static String bytes(num raw) {
    if (raw < 0) return '—';
    if (raw < 1024) return '${raw.toInt()} B';
    if (raw < 1024 * 1024) return '${(raw / 1024).toStringAsFixed(1)} KB';
    if (raw < 1024 * 1024 * 1024) {
      return '${(raw / (1024 * 1024)).toStringAsFixed(2)} MB';
    }
    return '${(raw / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  static String memory(int total, int used) {
    if (total <= 0) return '—';
    final totalMb = total / (1024 * 1024);
    final usedMb = used / (1024 * 1024);
    final percent = (used * 100 / total).round();
    return '${usedMb.toStringAsFixed(0)} / ${totalMb.toStringAsFixed(0)} MB ($percent%)';
  }

  static String load(double value) => value.toStringAsFixed(2);

  static String rate(int bytesDiff, int msDiff) {
    if (msDiff <= 0 || bytesDiff < 0) return '0 B/s';
    final bps = bytesDiff * 1000 / msDiff;
    return '${bytes(bps)}/s';
  }
}
