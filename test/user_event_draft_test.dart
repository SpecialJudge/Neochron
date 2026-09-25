import 'package:celechron/mod/user_event_draft.dart';
import 'package:celechron/mod/user_event_rule.dart';
import 'package:flutter_test/flutter_test.dart';

/// 编辑页的草稿与校验（`lib/mod/user_event_draft.dart`）。
///
/// 为什么这些校验值得逐条钉住：**校验漏了不会报错**，只会存进去一条
/// "永远不发生"或者"画不出来"的日程，用户在界面完全看不出哪里错了。
/// 最容易漏的正是"结束节次早于开始节次"这一条。
void main() {
  DateTime d(int month, int day) => DateTime(2026, month, day);

  UserEventDraft draft({
    String title = '学生会例会',
    DateTime? start,
    UserEventTimeMode mode = UserEventTimeMode.clock,
    int startPeriod = 1,
    int endPeriod = 1,
    String startClock = '19:00',
    String endClock = '20:30',
    int repeatPeriod = 1,
  }) =>
      UserEventDraft(
        title: title,
        startDate: start ?? d(9, 14),
        timeMode: mode,
        startPeriod: startPeriod,
        endPeriod: endPeriod,
        startClock: startClock,
        endClock: endClock,
        repeatPeriod: repeatPeriod,
      );

  group('合法草稿 -> 可落库的日程', () {
    test('基本字段都落对', () {
      final event = draft().build(now: DateTime(2026, 9, 25, 10, 0))!;
      expect(event.title, '学生会例会');
      expect(event.startDate, d(9, 14));
      expect(event.usesPeriod, isFalse);
      expect(event.startClock, '19:00');
      expect(event.endClock, '20:30');
      expect(event.repeatPeriod, 1);
      expect(event.createdAt, DateTime(2026, 9, 25, 10, 0));
      expect(event.updatedAt, event.createdAt);
    });

    test('★ 标题首尾空格被去掉（不去掉列表上会显示成怪样）', () {
      expect(draft(title: '  例会  ').build()!.title, '例会');
    });

    test('★ 周几一律按开始日期算，草稿给不给都不影响', () {
      // 2026-09-14 是周一；即使草稿里带的是别的日子，落库也必须是周一
      expect(draft(start: d(9, 14)).build()!.dayOfWeek, DateTime.monday);
      expect(draft(start: d(9, 16)).build()!.dayOfWeek, DateTime.wednesday);
    });

    test('新建两次得到不同 uid（连按两次保存不会互相覆盖）', () {
      final a = draft().build()!;
      final b = draft().build()!;
      expect(a.uid, isNot(b.uid));
      expect(a.uid.startsWith('evt-'), isTrue);
    });

    test('按节次那种：不带时刻', () {
      final event = draft(
        mode: UserEventTimeMode.period,
        startPeriod: 5,
        endPeriod: 6,
      ).build()!;
      expect(event.usesPeriod, isTrue);
      expect(event.startPeriod, 5);
      expect(event.endPeriod, 6);
      expect(event.startClock, isNull);
      expect(event.endClock, isNull);
    });
  });

  group('编辑既有日程：uid 与字段都要接得住', () {
    test('of() 把字段都读出来，build() 保留 uid', () {
      final original = draft(
        mode: UserEventTimeMode.period,
        startPeriod: 5,
        endPeriod: 6,
      ).build()!;
      final again = UserEventDraft.of(original);
      expect(again.uid, original.uid);
      expect(again.title, original.title);
      expect(again.timeMode, UserEventTimeMode.period);
      expect(again.startPeriod, 5);
      expect(again.endPeriod, 6);
      expect(again.build()!.uid, original.uid);
    });

    test('按时刻那种同样能往返', () {
      final original = draft().build()!;
      final again = UserEventDraft.of(original).build()!;
      expect(again.uid, original.uid);
      expect(again.startClock, '19:00');
      expect(again.endClock, '20:30');
    });
  });

  group('校验：拦得住"存了却看不见"的几种', () {
    test('标题空 / 纯空格都被拦，且只报一条', () {
      expect(draft(title: '').validate(), ['请填标题']);
      expect(draft(title: '   ').validate(), ['请填标题']);
      expect(draft(title: '').isValid, isFalse);
    });

    test('★ 结束节次早于开始节次被拦（漏了就会存进一条看不见的日程）', () {
      final bad = draft(mode: UserEventTimeMode.period, startPeriod: 6, endPeriod: 5);
      expect(bad.validate(), ['结束节次不能早于开始节次']);
      expect(bad.build(), isNull);
    });

    test('节次越界被拦', () {
      expect(
        draft(mode: UserEventTimeMode.period, startPeriod: 0, endPeriod: 1)
            .validate(),
        ['开始节次要在 1 到 16 之间'],
      );
      expect(
        draft(mode: UserEventTimeMode.period, startPeriod: 1, endPeriod: 99)
            .validate(),
        ['结束节次要在 1 到 16 之间'],
      );
    });

    test('节次相等是合法的（一节课那种）', () {
      expect(
        draft(mode: UserEventTimeMode.period, startPeriod: 5, endPeriod: 5).isValid,
        isTrue,
      );
    });

    test('时刻写坏被拦', () {
      expect(draft(startClock: '乱写').validate(),
          ['开始时刻填得不对（要像 19:00 这样）']);
      expect(draft(endClock: '25:00').validate(),
          ['结束时刻填得不对（要像 20:30 这样）']);
      expect(draft(startClock: '19:99').isValid, isFalse);
      expect(draft(startClock: '').isValid, isFalse);
    });

    test('时刻带秒是可以的（有些时间选择器会给秒）', () {
      expect(draft(startClock: '19:00:00', endClock: '20:30:00').isValid, isTrue);
    });

    test('不检查"开始晚于结束"，跨零点要合法', () {
      expect(draft(startClock: '23:00', endClock: '01:00').isValid, isTrue);
    });

    test('重复间隔越界被拦，0 与 8 合法', () {
      expect(draft(repeatPeriod: -1).validate(), ['重复间隔要在 0 到 8 周之间']);
      expect(draft(repeatPeriod: 99).validate(), ['重复间隔要在 0 到 8 周之间']);
      expect(draft(repeatPeriod: 0).isValid, isTrue);
      expect(draft(repeatPeriod: 8).isValid, isTrue);
    });

    test('截止日早于开始日被拦；等于开始日是合法的', () {
      final early = draft()..repeatUntil = d(9, 1);
      expect(early.validate(), ['重复截止日不能早于开始日期']);
      final same = draft()..repeatUntil = d(9, 14);
      expect(same.isValid, isTrue);
    });

    test('多处问题一起报出来（不是只报第一条）', () {
      final messy = draft(
        title: '',
        mode: UserEventTimeMode.period,
        startPeriod: 9,
        endPeriod: 2,
        repeatPeriod: 42,
      );
      expect(messy.validate().length, 3);
    });
  });

  group('造出来的日程真的能发生（与判定串一遍）', () {
    test('每周：开始日与下一周都发生', () {
      final event = draft().build()!;
      expect(UserEventRule.occursOn(event, d(9, 14)), isTrue);
      expect(UserEventRule.occursOn(event, d(9, 21)), isTrue);
    });

    test('每两周：隔一周不发生', () {
      final event = draft(repeatPeriod: 2).build()!;
      expect(UserEventRule.occursOn(event, d(9, 14)), isTrue);
      expect(UserEventRule.occursOn(event, d(9, 21)), isFalse);
      expect(UserEventRule.occursOn(event, d(9, 28)), isTrue);
    });

    test('只这一次：一年后都不再发生', () {
      final event = draft(repeatPeriod: 0).build()!;
      expect(event.isSingleOccurrence, isTrue);
      expect(UserEventRule.occursOn(event, d(9, 14)), isTrue);
      expect(UserEventRule.occursOn(event, DateTime(2027, 9, 14)), isFalse);
    });

    test('不设截止日 → 没有终点（D11 允许清空）', () {
      expect(draft().build()!.lastDay, isNull);
    });
  });

  group('给人看的说法', () {
    test('时刻与节次', () {
      expect(draft().timeLabel, '19:00-20:30');
      expect(
        draft(mode: UserEventTimeMode.period, startPeriod: 5, endPeriod: 5).timeLabel,
        '第 5 节',
      );
      expect(
        draft(mode: UserEventTimeMode.period, startPeriod: 5, endPeriod: 6).timeLabel,
        '第 5-6 节',
      );
    });

    test('重复说法', () {
      expect(draft(repeatPeriod: 0).repeatLabel, '只这一次');
      expect(draft(repeatPeriod: 1).repeatLabel, '每周');
      expect(draft(repeatPeriod: 2).repeatLabel, '每 2 周');
    });
  });

  test('setStartDate 只取日期部分', () {
    final moved = draft()..setStartDate(DateTime(2026, 9, 16, 23, 59));
    expect(moved.startDate, d(9, 16));
    expect(moved.startDate.hour, 0);
    expect(moved.build()!.dayOfWeek, DateTime.wednesday);
  });
}
