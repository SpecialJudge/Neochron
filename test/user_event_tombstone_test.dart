import 'package:celechron/mod/user_event_tombstone.dart';
import 'package:flutter_test/flutter_test.dart';

/// 自定义日程的删除墓碑（`lib/mod/user_event_tombstone.dart`）。
///
/// 为什么墓碑要带**删除时刻**而不是只存一个 uid 集合：
/// 「删完之后又编辑过的日程要能复活」这条规则（见 `UserEventMerge.merge`）
/// 没有时刻就无从判断。对应地，这里的合并规则是**同 uid 取更早的删除时刻**，
/// 理由写在实现顶部（防止一台设备反复删除把另一台的合法编辑无限压制）。
void main() {
  final t0 = DateTime(2026, 9, 20, 10, 0);
  final t1 = DateTime(2026, 9, 21, 10, 0);

  group('序列化往返', () {
    test('每个字段都回来', () {
      final tombstone = UserEventTombstone(uid: 'a', deletedAt: t1);
      final back = UserEventTombstone.fromMap(tombstone.toMap())!;
      expect(back.uid, 'a');
      expect(back.deletedAt, t1);
    });

    test('读不动就返回 null（调用方丢掉这一条）', () {
      expect(UserEventTombstone.fromMap(null), isNull);
      expect(
        UserEventTombstone.fromMap(<String, dynamic>{'deletedAt': 1}),
        isNull,
      );
      expect(
        UserEventTombstone.fromMap(<String, dynamic>{'uid': 'a'}),
        isNull,
      );
      expect(
        UserEventTombstone.fromMap(<String, dynamic>{'uid': '', 'deletedAt': 1}),
        isNull,
      );
    });
  });

  group('同步包格式（uid -> 毫秒）', () {
    test('往返一致', () {
      final wire = UserEventTombstone.toWire(
        [UserEventTombstone(uid: 'a', deletedAt: t1)],
      );
      expect(wire['a'], t1.millisecondsSinceEpoch);

      final back = UserEventTombstone.fromWire(wire);
      expect(back.length, 1);
      expect(back.single.uid, 'a');
      expect(back.single.deletedAt, t1);
    });

    test('空 / 形状不对 → 空表，不抛异常', () {
      expect(UserEventTombstone.fromWire(null), isEmpty);
      expect(
        UserEventTombstone.fromWire(<String, dynamic>{'x': '不是数字'}),
        isEmpty,
      );
      expect(
        UserEventTombstone.fromWire(<String, dynamic>{'': 123}),
        isEmpty,
      );
    });
  });

  group('合并：同 uid 取更早的删除时刻', () {
    test('同 uid 取更早', () {
      final merged = UserEventTombstone.merge({'a': t1}, {'a': t0});
      expect(merged['a'], t0);
    });

    test('只在一侧的键保留下来', () {
      final merged = UserEventTombstone.merge({'a': t1, 'b': t0}, {'c': t1});
      expect(merged.keys.toSet(), {'a', 'b', 'c'});
      expect(merged['b'], t0);
      expect(merged['c'], t1);
    });

    test('不修改传进来的那两份（纯函数）', () {
      final local = <String, DateTime>{'a': t1};
      final remote = <String, DateTime>{'a': t0};
      UserEventTombstone.merge(local, remote);
      expect(local['a'], t1, reason: '入参不该被改动');
      expect(remote['a'], t0);
    });

    test('幂等：合两次结果一样', () {
      final once = UserEventTombstone.merge({'a': t1}, {'a': t0});
      final twice = UserEventTombstone.merge(once, {'a': t0});
      expect(twice['a'], once['a']);
    });
  });

  group('清理过期墓碑', () {
    final now = DateTime(2026, 9, 25);

    test('超过保留期的丢掉、新的留着', () {
      final pruned = UserEventTombstone.prune(
        {
          'old': now.subtract(const Duration(days: 200)),
          'fresh': now.subtract(const Duration(days: 10)),
        },
        now: now,
        keepDays: 180,
      );
      expect(pruned.containsKey('old'), isFalse);
      expect(pruned.containsKey('fresh'), isTrue);
    });

    test('正好到期的那个按"保留"处理（边界偏保守）', () {
      final pruned = UserEventTombstone.prune(
        {'edge': now.subtract(const Duration(days: 180))},
        now: now,
        keepDays: 180,
      );
      expect(pruned.containsKey('edge'), isTrue);
    });

    test('空表进空表出', () {
      expect(UserEventTombstone.prune(const {}, now: now), isEmpty);
    });
  });
}
