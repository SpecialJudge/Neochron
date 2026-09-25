import 'package:celechron/mod/user_event.dart';
import 'package:celechron/mod/user_event_periods.dart';
import 'package:celechron/model/period.dart';
import 'package:flutter_test/flutter_test.dart';

/// 自定义日程 -> 可显示时段（`lib/mod/user_event_periods.dart`）。
///
/// 这一层最容易出的两类错：
/// 1. **节次↔钟点换算**（第 5 节到底是几点？换算表缺项时会不会硬算出一个错时间）；
/// 2. **发生日筛选**（哪几天铺到日历上，学期边界怎么收）。
/// 所以按这两块分开钉，末尾再补一小段到 `Period` 的转换（那部分逻辑为零）。
void main() {
  DateTime d(int month, int day) => DateTime(2026, month, day);

  /// 一份简化但**形状与真实校历一致**的节次表：
  /// 下标 = 第几节，`[0]` 空着不用；每节给 (开始, 结束) 两个偏移量。
  /// 数字取自真实校历的前 6 节（08:00-08:45、08:50-09:35、10:00-10:45、
  /// 10:50-11:35、11:40-12:25、13:25-14:10），够覆盖"连堂/跨饭点"两种情况。
  List<List<Duration>> times() {
    List<Duration> slot(int sh, int sm, int eh, int em) => [
          Duration(hours: sh, minutes: sm),
          Duration(hours: eh, minutes: em),
        ];
    return <List<Duration>>[
      <Duration>[], // 0：不用
      slot(8, 0, 8, 45),
      slot(8, 50, 9, 35),
      slot(10, 0, 10, 45),
      slot(10, 50, 11, 35),
      slot(11, 40, 12, 25),
      slot(13, 25, 14, 10),
    ];
  }

  UserEventCalendar cal({
    DateTime? first,
    DateTime? last,
    List<LectureTime> lectures = const <LectureTime>[],
  }) =>
      UserEventCalendar(
        semesterName: '2026-2027-1秋冬',
        firstDay: first ?? d(9, 14),
        lastDay: last ?? DateTime(2027, 1, 24),
        periodTimes: times(),
        lectures: lectures,
      );

  /// 按节次的日程。
  ///
  /// ⚠️ [endPeriod] 默认 **null**（结束跟开始同一节），**不要**给它一个像 5 这样的
  /// 固定默认值：那样 `startPeriod: 6` 会得到"第 6 节开始、第 5 节结束"这种
  /// 开始晚于结束的组合，被 [UserEventCalendar.spanOf] 按"单时刻"折成零长度，
  /// 于是冲突判定永远不成立 —— 这个坑我在验证程序里真的踩过一次，查了半天。
  UserEvent byPeriod(
    String uid, {
    DateTime? start,
    int repeatPeriod = 1,
    int startPeriod = 5,
    int? endPeriod,
    DateTime? until,
    String title = '学生会例会',
    String note = '',
    String location = '紫金港小剧场',
  }) =>
      UserEvent(
        uid: uid,
        title: title,
        startDate: start ?? d(9, 14),
        dayOfWeek: (start ?? d(9, 14)).weekday,
        startPeriod: startPeriod,
        endPeriod: endPeriod ?? startPeriod,
        repeatPeriod: repeatPeriod,
        repeatUntil: until,
        note: note,
        location: location,
      );

  UserEvent byClock(
    String uid, {
    DateTime? start,
    int repeatPeriod = 1,
    String from = '19:00',
    String to = '20:30',
    DateTime? until,
  }) =>
      UserEvent(
        uid: uid,
        title: '家教',
        startDate: start ?? d(9, 14),
        dayOfWeek: (start ?? d(9, 14)).weekday,
        startClock: from,
        endClock: to,
        repeatPeriod: repeatPeriod,
        repeatUntil: until,
      );

  group('节次 -> 钟点（换算表就是唯一口径）', () {
    test('第 5 节 = 11:40 开始、12:25 结束', () {
      final c = cal();
      final event = byPeriod('e1', startPeriod: 5, endPeriod: 5);
      expect(c.startAt(event, d(9, 14)), DateTime(2026, 9, 14, 11, 40));
      expect(c.endAt(event, d(9, 14)), DateTime(2026, 9, 14, 12, 25));
    });

    test('第 5-6 节：开始取第 5 节的开始、结束取第 6 节的结束（13:25-14:10）', () {
      final c = cal();
      final event = byPeriod('e1', startPeriod: 5, endPeriod: 6);
      expect(c.startAt(event, d(9, 14)), DateTime(2026, 9, 14, 11, 40));
      expect(c.endAt(event, d(9, 14)), DateTime(2026, 9, 14, 14, 10));
    });

    test('★ 换算表里没有这一节 → 返回 null，绝不猜一个时间出来', () {
      final c = cal();
      expect(c.startAt(byPeriod('e1', startPeriod: 99), d(9, 14)), isNull);
      expect(c.endAt(byPeriod('e1', startPeriod: 99), d(9, 14)), isNull);
      expect(c.spanOf(byPeriod('e1', startPeriod: 99), d(9, 14)), isNull);
    });

    test('结束节次缺省时跟开始节次走', () {
      final c = cal();
      final event = byPeriod('e1', startPeriod: 3, endPeriod: null);
      expect(c.startAt(event, d(9, 14)), DateTime(2026, 9, 14, 10, 0));
      expect(c.endAt(event, d(9, 14)), DateTime(2026, 9, 14, 10, 45));
    });
  });

  group('具体时刻 -> 钟点', () {
    test('19:00-20:30 落在当天', () {
      final c = cal();
      final event = byClock('e1');
      expect(c.startAt(event, d(9, 14)), DateTime(2026, 9, 14, 19, 0));
      expect(c.endAt(event, d(9, 14)), DateTime(2026, 9, 14, 20, 30));
    });

    test('只有开始时刻 → 结束等于开始（一个点）', () {
      final c = cal();
      final event = byClock('e1', to: '19:00');
      final span = c.spanOf(event, d(9, 14))!;
      expect(span.start, span.end);
      expect(span.duration, Duration.zero);
    });

    test('时刻写坏了 → null（不硬算）', () {
      final c = cal();
      expect(c.spanOf(byClock('e1', from: '乱写'), d(9, 14)), isNull);
      expect(c.spanOf(byClock('e1', from: '25:00'), d(9, 14)), isNull);
      expect(c.spanOf(byClock('e1', from: '19:99'), d(9, 14)), isNull);
      expect(c.spanOf(byClock('e1', from: ''), d(9, 14)), isNull);
    });

    test('parseClock 认得 "19:00:00" 也认得带空格', () {
      expect(UserEventCalendar.parseClock('19:00:00'), (19, 0));
      expect(UserEventCalendar.parseClock(' 08:05 '), (8, 5));
      expect(UserEventCalendar.parseClock(null), isNull);
      expect(UserEventCalendar.parseClock('19'), isNull);
    });
  });

  group('发生日筛选与时段展开', () {
    test('每周一次：一周里只有那一天有时段', () {
      final c = cal();
      final event = byPeriod('e1');
      final week = c.spansBetween([event], d(9, 14), d(9, 20));
      expect(week.length, 1);
      expect(week.single.day, d(9, 14));
    });

    test('每两周：两周里正好两次（9/14 与 9/28）', () {
      final c = cal();
      final event = byPeriod('e1', repeatPeriod: 2);
      // 区间右端必须**含到 9/28**：写成 9/27 会把第二次排除在外，
      // 于是只扫出 9/14、断言报"shorter than expected"。
      // （这个错我在验证程序与本测试里各犯过一次，注释留在这儿防第三次。）
      final spans = c.spansBetween([event], d(9, 14), d(9, 28));
      expect(spans.map((s) => s.day), [d(9, 14), d(9, 28)]);
    });

    test('每两周：中间那一周确实不铺（区间含到 9/28 时也只有两天）', () {
      final c = cal();
      final event = byPeriod('e1', repeatPeriod: 2);
      final spans = c.spansBetween([event], d(9, 14), d(9, 28));
      expect(spans.length, 2, reason: '9/21 那周不该有');
      expect(spans.map((s) => s.day).contains(d(9, 21)), isFalse);
    });

    test('★ 学期边界：超出学期的日子不铺', () {
      final c = cal(first: d(9, 14), last: d(9, 28));
      final event = byPeriod('e1');
      final spans = c.spansBetween([event], d(9, 1), DateTime(2026, 10, 31));
      expect(spans.map((s) => s.day), [d(9, 14), d(9, 21), d(9, 28)]);
    });

    test('clampToSemester = false 时不收边界（课表外的地方可能要用）', () {
      final c = cal(first: d(9, 14), last: d(9, 21));
      final event = byPeriod('e1');
      final spans = c.spansBetween(
        [event],
        d(9, 14),
        d(10, 5),
        clampToSemester: false,
      );
      expect(spans.length, 4);
    });

    test('截止日之后不再铺', () {
      final c = cal();
      final event = byPeriod('e1', until: d(9, 21));
      final spans = c.spansBetween([event], d(9, 14), DateTime(2026, 10, 12));
      expect(spans.map((s) => s.day), [d(9, 14), d(9, 21)]);
    });

    test('只有这一次：一整个学期只铺一天', () {
      final c = cal();
      final event = byPeriod('e1', repeatPeriod: 0);
      final spans = c.spansBetween([event], d(9, 1), DateTime(2027, 1, 24));
      expect(spans.map((s) => s.day), [d(9, 14)]);
    });

    test('多条日程合起来按开始时间升序', () {
      final c = cal();
      final morning = byPeriod('m', startPeriod: 1, endPeriod: 2);
      final noon = byPeriod('n', startPeriod: 5, endPeriod: 5);
      final evening = byClock('v');
      final spans = c.spansOfDay([evening, noon, morning], d(9, 14));
      expect(spans.map((s) => s.uid.split('@').first), ['m', 'n', 'v']);
    });

    test('那天不发生 → spanOf 返回 null', () {
      final c = cal();
      expect(c.spanOf(byPeriod('e1'), d(9, 15)), isNull);
    });
  });

  group('某一次的 uid 必须稳定（列表重建时不能变）', () {
    test('同一天问两次得到同一个 uid', () {
      final c = cal();
      final event = byPeriod('e1');
      final a = c.spanOf(event, d(9, 14))!;
      final b = c.spanOf(event, d(9, 14))!;
      expect(a.uid, b.uid);
      expect(a.uid, 'e1@20260914');
    });

    test('不同天的 uid 不同，且都带原始日程 uid', () {
      final c = cal();
      final event = byPeriod('e1');
      expect(c.spanOf(event, d(9, 14))!.uid, 'e1@20260914');
      expect(c.spanOf(event, d(9, 21))!.uid, 'e1@20260921');
      expect(c.spanOf(event, d(9, 21))!.fromUid, 'e1');
    });

    test('月份/日期补零（个位数不会写成 e1@202619）', () {
      final c = cal(first: d(9, 1), last: DateTime(2027, 1, 24));
      final event = byPeriod('e1', start: d(9, 9));
      expect(c.spanOf(event, d(9, 9))!.uid, 'e1@20260909');
    });
  });

  group('与课程冲突（SPEC.md D10）', () {
    /// 9/14 那天第 5-6 节有课（11:40-14:10 那段）
    List<LectureTime> mondayLecture() => [
          LectureTime(DateTime(2026, 9, 14, 13, 25),
              DateTime(2026, 9, 14, 14, 10)),
        ];

    test('日程与课重叠 → 判为冲突', () {
      final c = cal(lectures: mondayLecture());
      final event = byPeriod('e1', startPeriod: 6, endPeriod: 6); // 13:25-14:10
      expect(c.conflictsWithLecture(c.spanOf(event, d(9, 14))!), isTrue);
    });

    test('★ 首尾相接不算冲突（09:35 下课、09:35 开始）', () {
      final c = cal(lectures: [
        LectureTime(
            DateTime(2026, 9, 14, 8, 0), DateTime(2026, 9, 14, 9, 35)),
      ]);
      final touching = byClock('t', from: '09:35', to: '10:30');
      expect(c.conflictsWithLecture(c.spanOf(touching, d(9, 14))!), isFalse,
          reason: '接在课后开始的日程不该一直飘着冲突角标');
    });

    test('完全错开 → 不算冲突', () {
      final c = cal(lectures: mondayLecture());
      final event = byClock('e1', from: '19:00', to: '20:30');
      expect(c.conflictsWithLecture(c.spanOf(event, d(9, 14))!), isFalse);
    });

    test('conflictsOf 只挑出撞上的那些', () {
      final c = cal(lectures: mondayLecture());
      final hit = byPeriod('hit', startPeriod: 6, endPeriod: 6);
      final miss = byClock('miss');
      final picked = c.conflictsOf(c.spansOfDay([hit, miss], d(9, 14)));
      expect(picked.map((s) => s.fromUid), ['hit']);
    });

    test('没有任何课程时永不冲突', () {
      final c = cal();
      expect(c.conflictsWithLecture(c.spanOf(byPeriod('e1'), d(9, 14))!), isFalse);
    });
  });

  group('到 Period 的转换（逻辑为零，只确认字段对上）', () {
    test('字段一一对应，type 是 user', () {
      final c = cal();
      final span = c.spanOf(
        byPeriod('e1', note: '带水杯', title: '学生会例会'),
        d(9, 14),
      )!;
      final period = toPeriod(span);
      expect(period.uid, span.uid);
      expect(period.fromUid, 'e1');
      expect(period.type, PeriodType.user);
      expect(period.summary, '学生会例会');
      expect(period.description, '带水杯');
      expect(period.location, '紫金港小剧场');
      expect(period.startTime, span.start);
      expect(period.endTime, span.end);
    });

    test('批量转换保持顺序', () {
      final c = cal();
      final spans = c.spansOfDay(
        [byPeriod('a', startPeriod: 1, endPeriod: 1), byClock('b')],
        d(9, 14),
      );
      final periods = toPeriods(spans);
      expect(periods.map((p) => p.fromUid), ['a', 'b']);
    });

    test('固定粉是 #FFA6C9（SPEC.md R3）', () {
      expect(UserEventCalendar.eventColorArgb, 0xFFFFA6C9);
    });
  });
}
