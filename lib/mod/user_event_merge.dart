import 'package:celechron/mod/user_event.dart';

/// ============ 自定义日程的合并口径（纯逻辑，不碰 IO）============
///
/// 与待办（`DataMerge`）同一套规矩，理由也一样：
///
/// 1. **同 uid 比 `updatedAt`，新的赢**；
/// 2. **墓碑优先**：删过的不许被另一端带回来；
/// 3. **删完之后又改过的会复活**（判定见 [merge] 里的日期比较）；
/// 4. **合并是幂等的**：同一份数据合两次，结果一样。
///
/// 为什么单独开一个文件而不是塞进 `user_event_store.dart`：
/// store 那个文件要 import Hive 与 Get（`Get.find<DatabaseHelper>`），
/// 一旦混在一起，这段最容易算错的合并逻辑就**没法脱离 Flutter 环境单测**了，
/// 而它恰恰是"换台设备就丢数据/复活删掉的日程"这类事故的唯一防线。
/// （同样理由见 `user_event_date.dart` 顶部那段。）
class UserEventMerge {
  const UserEventMerge._();

  /// 把本地与远端两份日程合起来。
  ///
  /// [local] / [remote] 是**已经校验过**的 `UserEvent`（坏数据在 `fromMap` 那步就丢了）。
  /// [deletedUids] 是墓碑里的 uid 集合，`uid -> 删除时刻`。
  ///
  /// 返回结果按 `startDate` 升序（依次按 `title` 稳定排序），方便调用方直接落库。
  static List<UserEvent> merge({
    required Iterable<UserEvent> local,
    required Iterable<UserEvent> remote,
    Map<String, DateTime> deletedUids = const <String, DateTime>{},
  }) {
    final byUid = <String, UserEvent>{};

    // 先收本地、再收远端：同 uid 时比较 updatedAt
    for (final incoming in <UserEvent>[...local, ...remote]) {
      if (incoming.uid.isEmpty) continue;
      final existing = byUid[incoming.uid];
      if (existing == null) {
        byUid[incoming.uid] = incoming;
        continue;
      }
      if (incoming.updatedAt.isAfter(existing.updatedAt)) {
        byUid[incoming.uid] = incoming;
      }
    }

    // 墓碑：删得比"最后修改时间"更晚 → 这条保持删除
    //
    // 反过来（改得比删得更晚）说明用户删完之后又编辑过，应当**复活**，
    // 这与 `DataMerge.merge` 里对待办的口径一致。
    for (final entry in deletedUids.entries) {
      final event = byUid[entry.key];
      if (event == null) continue;
      if (!entry.value.isBefore(event.updatedAt)) {
        byUid.remove(entry.key);
      }
    }

    final result = byUid.values.toList()
      ..sort((a, b) {
        final byDate = a.startDate.compareTo(b.startDate);
        if (byDate != 0) return byDate;
        return a.title.compareTo(b.title);
      });
    return result;
  }

  /// 从列表里剔除已删除的（本地每次落盘/展示前都要过一道）。
  ///
  /// 与 [merge] 的墓碑规则**同源**：这里没有"远端"的概念，
  /// 所以只要墓碑不早于 `updatedAt` 就剔除。
  static List<UserEvent> visible(
    Iterable<UserEvent> events, {
    Map<String, DateTime> deletedUids = const <String, DateTime>{},
  }) {
    if (deletedUids.isEmpty) return events.toList();
    return events.where((event) {
      final deletedAt = deletedUids[event.uid];
      if (deletedAt == null) return true;
      return deletedAt.isBefore(event.updatedAt);
    }).toList();
  }
}
