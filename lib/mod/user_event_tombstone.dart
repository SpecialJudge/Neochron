import 'package:celechron/mod/user_event_date.dart';
import 'package:celechron/utils/json_utils.dart';

/// ============ 自定义日程的删除墓碑 ============
///
/// 为什么必须有它：同步只传"现存日程"时，另一端会把已被删除的日程**又推回来**。
/// 这与待办（`TaskTombstone`）、课程挂载（`CourseMountTombstone`）遇到的是同一个问题，
/// 口径也照它们办：删除先留一条「uid -> 删除时刻」。
///
/// 为什么**不是** `Set<String>` 而是一张 `uid -> 删除时刻` 的表：
/// 只有时刻才能判断"这个删除是不是比那条日程的最后修改更晚"。
/// 「删完之后又编辑过的日程要能复活」这条规则（见 `UserEventMerge.merge`）
/// 没有时刻就无从判断。待办的墓碑（`TaskTombstone`）本来就是带时间的，
/// 这里与它保持一致。
class UserEventTombstone {
  final String uid;
  final DateTime deletedAt;

  const UserEventTombstone({required this.uid, required this.deletedAt});

  Map<String, dynamic> toMap() => <String, dynamic>{
        'uid': uid,
        'deletedAt': deletedAt.millisecondsSinceEpoch,
      };

  /// 读不动就返回 `null`（由调用方丢掉这一条）
  static UserEventTombstone? fromMap(Map<dynamic, dynamic>? raw) {
    if (raw == null) return null;
    final uid = asString(raw['uid']);
    final millis = asInt(raw['deletedAt']);
    if (uid == null || uid.isEmpty || millis == null) return null;
    return UserEventTombstone(
      uid: uid,
      deletedAt: DateTime.fromMillisecondsSinceEpoch(millis),
    );
  }

  /// 给同步包用：`{uid: 删除时刻}`（纯数据，方便直接塞进 JSON）
  static Map<String, int> toWire(Iterable<UserEventTombstone> tombstones) =>
      <String, int>{
        for (final item in tombstones)
          if (item.uid.isNotEmpty) item.uid: item.deletedAt.millisecondsSinceEpoch,
      };

  /// 从同步包读回来（形状不对的整条丢掉）
  static List<UserEventTombstone> fromWire(Map<dynamic, dynamic>? raw) {
    if (raw == null) return const <UserEventTombstone>[];
    final result = <UserEventTombstone>[];
    raw.forEach((key, value) {
      final uid = key?.toString() ?? '';
      final millis = asInt(value);
      if (uid.isEmpty || millis == null) return;
      result.add(UserEventTombstone(
        uid: uid,
        deletedAt: DateTime.fromMillisecondsSinceEpoch(millis),
      ));
    });
    return result;
  }

  /// 合并两份墓碑：同 uid 取**更早**的那个删除时刻。
  ///
  /// 为什么取更早而不是更晚：墓碑的作用是"阻止复活"，取更早意味着
  /// 只要有一端删过就认这条删除，另一端后来再删一次不会把时刻往后推。
  /// 若把时刻推晚，会出现"一台设备反复删除、另一台的合法编辑被无限压制"。
  static Map<String, DateTime> merge(
    Map<String, DateTime> a,
    Map<String, DateTime> b,
  ) {
    final result = Map<String, DateTime>.from(a);
    for (final entry in b.entries) {
      final existing = result[entry.key];
      if (existing == null || entry.value.isBefore(existing)) {
        result[entry.key] = entry.value;
      }
    }
    return result;
  }

  /// 丢掉太老的墓碑（默认 180 天）。
  ///
  /// 墓碑不能无限长：一台设备删了一条日程，另一台半年都没上线，
  /// 那这条日程本来也不会再被看见了。这与"去重记录会过期清理"同一考虑。
  static Map<String, DateTime> prune(
    Map<String, DateTime> tombstones, {
    DateTime? now,
    int keepDays = 180,
  }) {
    final cutoff = userEventDateOnly(
      (now ?? DateTime.now()).subtract(Duration(days: keepDays)),
    );
    final result = <String, DateTime>{};
    for (final entry in tombstones.entries) {
      if (!entry.value.isBefore(cutoff)) result[entry.key] = entry.value;
    }
    return result;
  }
}
