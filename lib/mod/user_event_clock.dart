/// `"19:00"` / `"19:00:00"` -> `(19, 0)`；读不出来返回 `null`。
///
/// ============ 为什么单独一个文件 ============
///
/// 它同时被两处用：
/// - `user_event_periods.dart`（把时刻换成钟点去画）；
/// - `user_event_draft.dart`（编辑页保存前校验）。
///
/// 而草稿那一层必须**保持纯 Dart**（不然编辑页的校验就只能靠真机试，
/// 而校验错了的后果是"存进去一条永远不发生的日程"）。所以抽成一个
/// 谁都不依赖的叶子文件，与 `user_event_date.dart` 同一个套路。
///
/// 容忍 `"19:00:00"`（有些时间选择器会给秒）与首尾空格；
/// **不做任何猜测**：认不出来就是 null，由调用方决定报错还是拒绝保存。
(int, int)? userEventParseClock(String? clock) {
  if (clock == null) return null;
  final text = clock.trim();
  if (text.isEmpty) return null;
  final parts = text.split(':');
  if (parts.length < 2) return null;
  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour == null || minute == null) return null;
  if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
  return (hour, minute);
}

/// `(19, 0)` -> `"19:00"`（补零，便于存字符串与显示）
String userEventFormatClock(int hour, int minute) =>
    '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
