import 'package:celechron/mod/user_event.dart';
import 'package:celechron/mod/user_event_merge.dart';
import 'package:flutter_test/flutter_test.dart';

/// 自定义日程的**合并口径**（同步与导入的地基）。
///
/// 这一段算错，用户的表现是「换台设备就丢日程」或者「删掉的日程自己回来了」，
/// 而且极难当场发现（要两台设备同时在线才看得出来）。
/// 所以四条规矩各钉一遍：同 uid 比时间、墓碑优先、删后编辑复活、合并幂等。
///
/// 对应实现：`lib/mod/user_event_merge.dart`（纯逻辑，不碰 Hive 与 Get）。
void main() {
  final t0 = DateTime(2026, 9, 20, 10, 0);
  final t1 = DateTime(2026, 9, 21, 10, 0);

  UserEvent ev(
    String uid, {
    String title = '例会',
    DateTime? start,
    DateTime? updated,
  }) =>
      UserEvent(
        uid: uid,
        title: title,
        startDate: start ?? DateTime(2026, 9, 14),
        dayOfWeek: (start ?? DateTime(2026, 9, 14)).weekday,
        startPeriod: 5,
        endPeriod: 6,
        updatedAt: updated ?? t0,
      );

  List<String> uids(List<UserEvent> events) =>
      events.map((event) => event.uid).toList();

  group('取并集：谁都不丢、也不重复', () {
    test('本地空 + 远端两条 → 两条', () {
      expect(
        uids(UserEventMerge.merge(
          local: const [],
          remote: [ev('a'), ev('b')],
        )),
        ['a', 'b'],
      );
    });

    test('两边完全一样 → 只有一条', () {
      final a = ev('a');
      expect(uids(UserEventMerge.merge(local: [a], remote: [a])), ['a']);
    });

    test('本地独有 + 远端独有 → 都在', () {
      expect(
        uids(UserEventMerge.merge(local: [ev('a')], remote: [ev('b')])),
        ['a', 'b'],
      );
    });
  });

  group('同 uid：updatedAt 新的赢', () {
    test('远端更新 → 取远端', () {
      final merged = UserEventMerge.merge(
        local: [ev('a', title: '旧的', updated: t0)],
        remote: [ev('a', title: '新的', updated: t1)],
      );
      expect(merged.single.title, '新的');
    });

    test('本地更新 → 保留本地（不被远端旧数据顶掉）', () {
      final merged = UserEventMerge.merge(
        local: [ev('a', title: '本地的', updated: t1)],
        remote: [ev('a', title: '远端的', updated: t0)],
      );
      expect(merged.single.title, '本地的');
    });

    test('时间完全相同 → 留一条，不炸', () {
      final merged = UserEventMerge.merge(
        local: [ev('a', updated: t0)],
        remote: [ev('a', updated: t0)],
      );
      expect(merged.length, 1);
    });
  });

  group('墓碑：删过的不许被另一端带回来', () {
    test('墓碑晚于最后修改 → 这条保持删除', () {
      final merged = UserEventMerge.merge(
        local: [ev('a', updated: t0)],
        remote: const [],
        deletedUids: {'a': t1},
      );
      expect(merged, isEmpty);
    });

    test('★ 删完之后又编辑过的会复活（墓碑比修改更早）', () {
      final merged = UserEventMerge.merge(
        local: [ev('a', title: '删了又改', updated: t1)],
        remote: const [],
        deletedUids: {'a': t0},
      );
      expect(uids(merged), ['a']);
    });

    test('墓碑时刻与修改时刻相同时也算删除（相等时偏向删除）', () {
      final merged = UserEventMerge.merge(
        local: [ev('a', updated: t0)],
        remote: const [],
        deletedUids: {'a': t0},
      );
      expect(merged, isEmpty);
    });

    test('墓碑对远端那份同样生效（另一端删的，本地也要删）', () {
      final merged = UserEventMerge.merge(
        local: const [],
        remote: [ev('a', updated: t0)],
        deletedUids: {'a': t1},
      );
      expect(merged, isEmpty);
    });

    test('墓碑指向不存在的 uid → 不影响别的', () {
      final merged = UserEventMerge.merge(
        local: [ev('a'), ev('b')],
        remote: const [],
        deletedUids: {'查无此人': t1},
      );
      expect(uids(merged), ['a', 'b']);
    });
  });

  group('排序与脏数据', () {
    test('按开始日期升序', () {
      final merged = UserEventMerge.merge(
        local: [
          ev('late', start: DateTime(2026, 10, 5)),
          ev('early', start: DateTime(2026, 9, 7)),
        ],
        remote: const [],
      );
      expect(uids(merged), ['early', 'late']);
    });

    test('同一天按标题稳定排序', () {
      final merged = UserEventMerge.merge(
        local: [ev('u1', title: 'B 会'), ev('u2', title: 'A 会')],
        remote: const [],
      );
      expect(uids(merged), ['u2', 'u1']);
    });

    test('空 uid 直接跳过（脏数据）', () {
      expect(
        uids(UserEventMerge.merge(local: [ev('')], remote: const [])),
        isEmpty,
      );
    });
  });

  group('幂等：同一份数据合两次，结果一样', () {
    test('第二次合并不改变结果', () {
      final local = [ev('a', updated: t0)];
      final remote = [ev('a', title: '远端改过', updated: t1), ev('b')];
      final once = UserEventMerge.merge(local: local, remote: remote);
      final twice = UserEventMerge.merge(local: once, remote: remote);
      expect(uids(twice), uids(once));
      expect(
        twice.map((event) => event.title).join(','),
        once.map((event) => event.title).join(','),
      );
    });
  });

  group('visible：本地展示前过一道墓碑', () {
    test('被删的剔除、其余保留', () {
      final list = [ev('a'), ev('b')];
      expect(
        uids(UserEventMerge.visible(list, deletedUids: {'a': t1})),
        ['b'],
      );
    });

    test('没有墓碑时原样返回', () {
      expect(uids(UserEventMerge.visible([ev('a'), ev('b')])), ['a', 'b']);
    });
  });
}
