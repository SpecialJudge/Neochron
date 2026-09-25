import 'package:celechron/database/database_helper.dart';
import 'package:celechron/mod/user_event.dart';
import 'package:celechron/mod/user_event_merge.dart';
import 'package:celechron/mod/user_event_tombstone.dart';
import 'package:celechron/mod/lan_sync_client.dart';

/// ============ 自定义日程的读写入口 ============
///
/// 只管"存哪里、怎么取"，不管界面（与 `course_mount_store.dart` 同一分工）。
///
/// 存储方式照 `CourseMount` 的先例：**独立 box + 值存一份 Map/JSON**，
/// **不新增 Hive typeId、不注册 adapter**。好处是零 schema 风险、零迁移脚本，
/// 以后给 `UserEvent` 加字段不用动 Hive 编号。
/// （理由的完整版见 `lib/model/course_mount.dart` 顶部那段。）
///
/// 两个盒子：
/// - `userEventBox`：键 = uid，值 = `UserEvent.toMap()`
/// - `userEventTombstoneBox`：键 = uid，值 = `UserEventTombstone.toMap()`
extension UserEventStore on DatabaseHelper {
  // ------------------------------------------------------------ 读

  /// 取一条日程；没有就返回 `null`（读不动的脏数据也按"没有"处理）
  UserEvent? userEvent(String uid) {
    if (uid.isEmpty) return null;
    final raw = userEventBox.get(uid);
    if (raw is! Map) return null;
    return UserEvent.fromMap(raw);
  }

  /// 全部日程，按开始日期升序（同日的按标题稳定排序）。
  ///
  /// 已经剔除墓碑删掉的（[deletedUserEventUids]），所以调用方拿到的一定是
  /// "看得见的那些"，不用自己再过滤一遍。
  List<UserEvent> userEvents() {
    final all = <UserEvent>[];
    for (final raw in userEventBox.values) {
      if (raw is! Map) continue;
      final event = UserEvent.fromMap(raw);
      // 单条脏数据只丢它自己，不让整张表崩（这是用户数据）
      if (event != null) all.add(event);
    }
    final visible = UserEventMerge.visible(
      all,
      deletedUids: deletedUserEventUids(),
    );
    visible.sort((a, b) {
      final byDate = a.startDate.compareTo(b.startDate);
      if (byDate != 0) return byDate;
      return a.title.compareTo(b.title);
    });
    return visible;
  }

  /// 某个学期的日程（`semesterName` 对得上，或没写学期的那种"不限学期"）
  List<UserEvent> userEventsOfSemester(String? semesterName) => userEvents()
      .where((event) =>
          event.semesterName == null ||
          semesterName == null ||
          event.semesterName == semesterName)
      .toList();

  /// 墓碑：`uid -> 删除时刻`
  Map<String, DateTime> deletedUserEventUids() {
    final result = <String, DateTime>{};
    for (final raw in userEventTombstoneBox.values) {
      if (raw is! Map) continue;
      final tombstone = UserEventTombstone.fromMap(raw);
      if (tombstone != null) result[tombstone.uid] = tombstone.deletedAt;
    }
    return result;
  }

  // ------------------------------------------------------------ 写

  /// 存一条（新建或修改都走这里）。
  ///
  /// **同一 uid 再存一次就是"编辑"**，所以顺手把这条的墓碑清掉：
  /// 用户"删了又建回来"或"删完在另一台改了"时，墓碑不该继续压着它。
  /// 这一步不能漏，否则会出现"日程明明保存成功、界面上却没有"。
  Future<void> saveUserEvent(UserEvent event) async {
    if (event.uid.isEmpty) return;
    await userEventBox.put(event.uid, event.toMap());
    if (userEventTombstoneBox.containsKey(event.uid)) {
      await userEventTombstoneBox.delete(event.uid);
    }
    // 自定义日程是用户数据：存完让局域网同步推一次
    // （与 saveCourseMount 同一口径，见 LanSyncClient.scheduleSync）
    LanSyncClient.instance.scheduleSync();
  }

  /// 删一条：先留墓碑，再删本体。
  ///
  /// 顺序很重要：先删本体、后写墓碑的话，中间那一瞬间崩溃就会留下
  /// "删了但没墓碑"的状态 —— 另一台设备一同步就把它带回来了。
  Future<void> deleteUserEvent(String uid, {DateTime? now}) async {
    if (uid.isEmpty) return;
    final at = now ?? DateTime.now();
    await userEventTombstoneBox
        .put(uid, UserEventTombstone(uid: uid, deletedAt: at).toMap());
    await userEventBox.delete(uid);
    LanSyncClient.instance.scheduleSync();
  }

  /// 收下对方那份墓碑（并集，同 uid 取更早的删除时刻）。
  Future<void> adoptUserEventTombstones(Iterable<UserEventTombstone> incoming) async {
    final mine = <String, DateTime>{};
    for (final raw in userEventTombstoneBox.values) {
      if (raw is! Map) continue;
      final tombstone = UserEventTombstone.fromMap(raw);
      if (tombstone != null) mine[tombstone.uid] = tombstone.deletedAt;
    }
    final incomingMap = <String, DateTime>{
      for (final item in incoming)
        if (item.uid.isNotEmpty) item.uid: item.deletedAt,
    };
    final merged = UserEventTombstone.merge(mine, incomingMap);
    for (final entry in merged.entries) {
      if (mine[entry.key] == entry.value) continue;
      await userEventTombstoneBox.put(
        entry.key,
        UserEventTombstone(uid: entry.key, deletedAt: entry.value).toMap(),
      );
    }
  }

  /// 清理过期墓碑（默认 180 天），返回清掉几条。
  ///
  /// 什么时候调用：启动时或每次同步后都行，代价很小。
  Future<int> pruneUserEventTombstones({int keepDays = 180}) async {
    final all = deletedUserEventUids();
    final kept = UserEventTombstone.prune(all, keepDays: keepDays);
    var removed = 0;
    for (final uid in all.keys) {
      if (kept.containsKey(uid)) continue;
      await userEventTombstoneBox.delete(uid);
      removed++;
    }
    return removed;
  }

  /// 一次性把本地的日程与墓碑塞进同步包（第 6 步会用到）。
  ///
  /// 形状与 `CourseMount` 那一套一致：值都是纯 Map，不新增 Hive 类型。
  ({
    List<Map<String, dynamic>> events,
    Map<String, int> tombstones,
  }) userEventSyncPayload() {
    final events = <Map<String, dynamic>>[];
    for (final raw in userEventBox.values) {
      if (raw is! Map) continue;
      final event = UserEvent.fromMap(raw);
      if (event != null) events.add(event.toMap());
    }
    return (
      events: events,
      tombstones: UserEventTombstone.toWire(
        deletedUserEventUids()
            .entries
            .map((entry) =>
                UserEventTombstone(uid: entry.key, deletedAt: entry.value)),
      ),
    );
  }
}
