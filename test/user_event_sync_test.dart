import 'dart:convert';

import 'package:celechron/mod/user_event.dart';
import 'package:celechron/mod/user_event_merge.dart';
import 'package:celechron/mod/user_event_tombstone.dart';
import 'package:celechron/utils/data_sync.dart';
import 'package:flutter_test/flutter_test.dart';

/// 自定义日程的**同步契约**（`DataBundle` 的那两个新字段，SPEC.md 步 6）。
///
/// `DataBundle` 是「导出/导入」与「局域网同步」共用的载体，所以这两个字段
/// 一加上，两条路都覆盖到了（局域网那边的公共入口
/// `mergeIncomingBundle` 调的也是 `DataBackup.applyMerge(bundle: …)`）。
///
/// 这里钉三件事：
/// 1. **只加字段**：老备份（没有这两个键）照样能导入，新字段能完整往返；
/// 2. **脏数据不许把整包搞崩**：单条日程坏了就丢那一条；
/// 3. 合并在「跨设备」这个场景下真的不丢：新增、更新、墓碑、幂等。
void main() {
  final t0 = DateTime(2026, 9, 25, 10, 0);
  final t1 = DateTime(2026, 9, 25, 11, 0);

  UserEvent makeEvent({
    String uid = 'e1',
    String title = '学生会例会',
    DateTime? updatedAt,
    DateTime? until,
    int repeatPeriod = 1,
  }) =>
      UserEvent(
        uid: uid,
        title: title,
        startDate: DateTime(2026, 9, 14),
        dayOfWeek: DateTime.monday,
        startClock: '19:00',
        endClock: '20:30',
        repeatPeriod: repeatPeriod,
        repeatUntil: until,
        location: '紫金港小剧场',
        updatedAt: updatedAt ?? t0,
        createdAt: t0,
      );

  DataBundle makeBundle({
    List<Map<String, dynamic>> userEvents = const [],
    Map<String, int> userEventTombstones = const {},
  }) =>
      DataBundle(
        exportedAt: t0,
        deviceId: 'device-a',
        tasks: const [],
        tombstones: const [],
        tags: const [],
        tagColors: const {},
        reminderMode: 0,
        alarmTheme: 'elysia',
        userEvents: userEvents,
        userEventTombstones: userEventTombstones,
      );

  group('契约：新字段进包、也读得回来', () {
    test('日程完整往返（字段一个都不丢）', () {
      final event = makeEvent(until: DateTime(2026, 12, 21), repeatPeriod: 2);
      final back = DataBundle.decode(
        makeBundle(userEvents: [event.toMap()]).encode(),
      )!;

      expect(back.userEvents.length, 1);
      final restored = UserEvent.fromMap(back.userEvents.single)!;
      expect(restored.uid, event.uid);
      expect(restored.title, event.title);
      expect(restored.startDate, event.startDate);
      expect(restored.dayOfWeek, event.dayOfWeek);
      expect(restored.startClock, '19:00');
      expect(restored.endClock, '20:30');
      expect(restored.repeatPeriod, 2);
      expect(restored.repeatUntil, event.repeatUntil);
      expect(restored.location, '紫金港小剧场');
    });

    test('墓碑带着**删除时刻**往返（少了它就判断不了"删后编辑要复活"）', () {
      final wire = UserEventTombstone.toWire(
        [UserEventTombstone(uid: 'e1', deletedAt: t1)],
      );
      final back = DataBundle.decode(
        makeBundle(userEventTombstones: wire).encode(),
      )!;
      expect(back.userEventTombstones['e1'], t1.millisecondsSinceEpoch);

      final restored = UserEventTombstone.fromWire(back.userEventTombstones);
      expect(restored.single.deletedAt, t1);
    });

    test('★ 老备份（完全没有这两个键）照样能导入，读出来是空表', () {
      final json = jsonDecode(makeBundle().encode()) as Map<String, dynamic>;
      json.remove('userEvents');
      json.remove('userEventTombstones');
      final back = DataBundle.decode(jsonEncode(json))!;
      expect(back.userEvents, isEmpty);
      expect(back.userEventTombstones, isEmpty);
    });

    test('包里的脏数据（形状不对）被丢掉，不影响整包', () {
      final json = jsonDecode(makeBundle().encode()) as Map<String, dynamic>;
      // 形状不对：不是 Map；以及一个缺 uid 的 Map
      json['userEvents'] = <dynamic>[
        '这不是一条日程',
        123,
        <String, dynamic>{'title': '缺 uid'},
      ];
      final back = DataBundle.decode(jsonEncode(json))!;
      // DataBundle 只负责装进列表，能不能解析由 UserEvent.fromMap 决定
      expect(back.userEvents.length, 1);
      expect(UserEvent.fromMap(back.userEvents.single), isNull);
    });

    test('墓碑值不是数字时忽略那一条，不炸', () {
      final json = jsonDecode(makeBundle().encode()) as Map<String, dynamic>;
      json['userEventTombstones'] = <String, dynamic>{
        'e1': '不是数字',
        'e2': 1234,
      };
      final back = DataBundle.decode(jsonEncode(json))!;
      expect(back.userEventTombstones.containsKey('e1'), isFalse);
      expect(back.userEventTombstones['e2'], 1234);
    });
  });

  group('跨设备合并不丢数据（导入与局域网同步都走这一套）', () {
    test('本机没有、对方有 → 加进来', () {
      final merged = UserEventMerge.merge(
        local: const [],
        remote: [makeEvent(uid: 'remote-1'), makeEvent(uid: 'remote-2')],
      );
      expect(merged.map((e) => e.uid).toList(), ['remote-1', 'remote-2']);
    });

    test('两边都有同一条 → 只留一条，且取更新的那份', () {
      final merged = UserEventMerge.merge(
        local: [makeEvent(title: '手机上改的', updatedAt: t0)],
        remote: [makeEvent(title: '电脑上改的', updatedAt: t1)],
      );
      expect(merged.length, 1);
      expect(merged.single.title, '电脑上改的');
    });

    test('★ 对方删过的不会在本机复活（墓碑跟着包一起过来）', () {
      final merged = UserEventMerge.merge(
        local: [makeEvent(uid: 'e1', updatedAt: t0)],
        remote: const [],
        deletedUids: {'e1': t1},
      );
      expect(merged, isEmpty);
    });

    test('★ 删完之后又编辑过的会复活（墓碑比 updatedAt 早）', () {
      final merged = UserEventMerge.merge(
        local: [makeEvent(uid: 'e1', updatedAt: t1)],
        remote: const [],
        deletedUids: {'e1': t0},
      );
      expect(merged.single.uid, 'e1');
    });

    test('同一份数据合两次结果一样（幂等）—— 反复同步不会长出重复条目', () {
      final local = [makeEvent(uid: 'e1', updatedAt: t1)];
      final remote = [makeEvent(uid: 'e2'), makeEvent(uid: 'e1', updatedAt: t0)];
      final once = UserEventMerge.merge(local: local, remote: remote);
      final twice = UserEventMerge.merge(local: once, remote: remote);
      expect(twice.map((e) => e.uid).toList(), once.map((e) => e.uid).toList());
      expect(twice.length, once.length);
    });

    test('两边的墓碑合起来（同 uid 取更早的删除时刻）', () {
      final merged = UserEventTombstone.merge({'e1': t1}, {'e1': t0, 'e2': t1});
      expect(merged['e1'], t0);
      expect(merged['e2'], t1);
      expect(merged.length, 2);
    });

    test('只要一边有、另一边没有的日程都保留（谁都不丢）', () {
      final merged = UserEventMerge.merge(
        local: [makeEvent(uid: 'only-local')],
        remote: [makeEvent(uid: 'only-remote')],
      );
      expect(merged.map((e) => e.uid).toSet(), {'only-local', 'only-remote'});
    });
  });

  group('同步包不会顺手把日程塞进不该去的地方', () {
    test('日程不进 secrets（密钥白名单仍然只有那五个键）', () {
      expect(SyncSecrets.allowed.contains('userEvents'), isFalse);
      expect(
        SyncSecrets.filter({'userEvents': 'x', SyncSecrets.aiApiKey: 'sk-1'}),
        {SyncSecrets.aiApiKey: 'sk-1'},
      );
    });

    test('格式标识没有被动过（改了会让用户已有备份与旧客户端全部被拒）', () {
      expect(DataBundle.format, 'celechron-mod');
    });
  });
}
