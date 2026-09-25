import 'package:celechron/mod/user_event.dart';
import 'package:celechron/mod/user_event_periods.dart';
import 'package:celechron/mod/user_event_timetable.dart';
import 'package:flutter_test/flutter_test.dart';

/// 课表格子里的行区间计算（`lib/mod/user_event_timetable.dart`，SPEC.md 步 5）。
///
/// 课表是「15 行 × 周一到周日」的固定格子，一行 = 一节课
/// （2026-09-25 用户拍板从 13 行扩到 15 行，与真实校历的 15 节一致）。
/// 这一段最容易算错的地方是**边界**：
/// - 20:30 既是第 12 节的下课、又是第 13 节的开始 —— 取错会让一段
///   19:00-20:30 的例会白占三行（看着比实际长一倍）；
/// - 12:25 既是第 5 节的下课、又是第 6 节的开始 —— 取错会让"12:25 开始的会"
///   画到上一节去；
/// - 早于第一节课 / 晚于最后一节课的日程要**夹到边界**，不能整条消失。
///
/// 这四条都是实现时实测踩过的，所以逐条钉住。
void main() {
  DateTime d(int month, int day) => DateTime(2026, month, day);

  /// **真实校历**的节次起止（`assets/calendar/*.json` 的 `sessionTime` 原文）。
  ///
  /// ⚠️ 必须用真表：我第一版凭印象编了一张（把第 12 节写成 19:40-**20:30**），
  /// 于是推出了一条错误的规则，靠测试才发现对不上。真实情况是第 12 节
  /// 19:40-**20:25**，第 13 节 20:30 开始 —— 中间有 5 分钟课间，
  /// 所以"20:30 结束"根本不被任何一节包含。这一段教训也写在实现顶部。
  const rawSlots = <List<String>>[
    ['00:00', '00:00'], // 下标 0 空着不用
    ['08:00', '08:45'], ['08:50', '09:35'], ['10:00', '10:45'],
    ['10:50', '11:35'], ['11:40', '12:25'], ['13:25', '14:10'],
    ['14:15', '15:00'], ['15:05', '15:50'], ['16:15', '17:00'],
    ['17:05', '17:50'], ['18:50', '19:35'], ['19:40', '20:25'],
    ['20:30', '21:15'], ['21:20', '22:05'], ['22:10', '22:55'],
  ];

  Duration hm(String text) {
    final parts = text.split(':');
    return Duration(hours: int.parse(parts[0]), minutes: int.parse(parts[1]));
  }

  List<List<Duration>> times() =>
      rawSlots.map((slot) => <Duration>[hm(slot[0]), hm(slot[1])]).toList();

  UserEventCalendar cal() => UserEventCalendar(
        semesterName: '2026-2027-1秋冬',
        firstDay: d(9, 14),
        lastDay: DateTime(2027, 1, 24),
        periodTimes: times(),
      );

  UserEvent byPeriod(String uid, {int startPeriod = 5, int? endPeriod}) =>
      UserEvent(
        uid: uid,
        title: '学生会例会',
        startDate: d(9, 14),
        dayOfWeek: DateTime.monday,
        startPeriod: startPeriod,
        endPeriod: endPeriod ?? startPeriod,
        repeatPeriod: 1,
      );

  UserEvent byClock(String uid, {String from = '19:00', String to = '20:30'}) =>
      UserEvent(
        uid: uid,
        title: '学生会例会',
        startDate: d(9, 14),
        dayOfWeek: DateTime.monday,
        startClock: from,
        endClock: to,
        repeatPeriod: 1,
      );

  /// 把一条日程的行区间写成 `5-6` 这种
  String rowsOf(UserEvent event) {
    final span = cal().spanOf(event, d(9, 14));
    if (span == null) return 'span=null';
    final rows = TimetableRowLayout.rowsOfSpan(span, times());
    return rows == null ? 'null' : '${rows.first}-${rows.last}';
  }

  group('按节次：端点正好等于某一节的首/尾', () {
    test('第 5 节 → 5-5', () => expect(rowsOf(byPeriod('a', startPeriod: 5)), '5-5'));
    test('第 5-6 节 → 5-6',
        () => expect(rowsOf(byPeriod('a', startPeriod: 5, endPeriod: 6)), '5-6'));
    test('第 1-2 节 → 1-2',
        () => expect(rowsOf(byPeriod('a', startPeriod: 1, endPeriod: 2)), '1-2'));
    test('第 11-12 节 → 11-12',
        () => expect(rowsOf(byPeriod('a', startPeriod: 11, endPeriod: 12)), '11-12'));
    test('第 13 节（最后一节）→ 13-13',
        () => expect(rowsOf(byPeriod('a', startPeriod: 13)), '13-13'));
  });

  group('按时刻：反查落进哪几节', () {
    test('19:00-20:30 → 11-13（结束 20:30 正是第 13 节上课，离它最近）', () {
      // 20:30 离第 12 节下课（20:25）5 分钟、离第 13 节上课（20:30）0 分钟
      // → 取第 13 节。这正是"例会开到 20:30"该有的样子。
      expect(rowsOf(byClock('b')), '11-13');
    });

    test('★ 开始时刻正好是某节下课（12:25 = 第 5 节最后一刻）取第 5 节', () {
      // 12:25 离第 5 节下课 0 分钟、离第 6 节上课（13:25）60 分钟 → 取第 5 节。
      // 规则的准确说法是"取距离最近的节边界，平局取靠前"，见实现顶部。
      expect(rowsOf(byClock('b', from: '12:25', to: '14:10')), '5-6');
    });

    test('★ 5 分钟课间里的钟点：19:37 离第 11 节下课 2 分钟、离第 12 节上课 3 分钟', () {
      expect(rowsOf(byClock('b', from: '19:37', to: '20:00')), '11-12',
          reason: '起贴第 11 节，止落在第 12 节（19:40-20:25）里');
    });

    test('08:00-09:35 → 1-2', () {
      expect(rowsOf(byClock('b', from: '08:00', to: '09:35')), '1-2');
    });

    test('正好占一节：10:00-10:45 → 3-3', () {
      expect(rowsOf(byClock('b', from: '10:00', to: '10:45')), '3-3');
    });

    test('正好占一节：11:40-12:25 → 5-5', () {
      expect(rowsOf(byClock('b', from: '11:40', to: '12:25')), '5-5');
    });

    test('正好占一节：13:25-14:10 → 6-6', () {
      expect(rowsOf(byClock('b', from: '13:25', to: '14:10')), '6-6');
    });

    test('正好占一节：19:40-20:25 → 12-12', () {
      expect(rowsOf(byClock('b', from: '19:40', to: '20:25')), '12-12');
    });

    test('跨饭点 12:00-13:30 → 5-6', () {
      expect(rowsOf(byClock('b', from: '12:00', to: '13:30')), '5-6');
    });

    test('单时刻（起止相同）只占一行', () {
      expect(rowsOf(byClock('b', from: '19:00', to: '19:00')), '11-11');
    });

    test('★ 早于第一节课 → 夹到第一节，不整条消失', () {
      expect(rowsOf(byClock('b', from: '07:00', to: '07:30')), '1-1');
    });

    test('★ 晚于最后一节课 → 夹到最后一节，不整条消失', () {
      expect(rowsOf(byClock('b', from: '23:30', to: '23:59')), '15-15');
    });

    test('跨越整天（畸形输入）→ 给出 1-15，仍然不返回 null', () {
      expect(rowsOf(byClock('b', from: '06:00', to: '23:00')), '1-15');
    });
  });

  group('换算表不正常时不硬画', () {
    test('换算表完全为空 → null（真的没地方画）', () {
      final span = cal().spanOf(byClock('b'), d(9, 14))!;
      expect(
        TimetableRowLayout.rowsOfSpan(span, <List<Duration>>[<Duration>[]]),
        isNull,
      );
    });

    test('只有 1 节的表：落在它之外 → 夹到 1-1，而不是 null', () {
      final span = EventSpan(
        uid: 'x@20260914',
        fromUid: 'x',
        title: '例会',
        note: '',
        location: '',
        start: DateTime(2026, 9, 14, 10, 0),
        end: DateTime(2026, 9, 14, 10, 45),
        day: d(9, 14),
      );
      final rows = TimetableRowLayout.rowsOfSpan(span, <List<Duration>>[
        <Duration>[],
        [const Duration(hours: 8), const Duration(hours: 8, minutes: 45)],
      ]);
      expect(rows, isNotNull);
      expect('${rows!.first}-${rows.last}', '1-1');
    });
  });

  group('layoutUserEvents：排序、重叠、weekday', () {
    test('按第一行升序，行区间与 weekday 都对', () {
      final c = cal();
      final cells = TimetableRowLayout.layoutUserEvents(
        weekday: 3,
        spans: [
          c.spanOf(byClock('evening'), d(9, 14))!,
          c.spanOf(byPeriod('noon', startPeriod: 5), d(9, 14))!,
          c.spanOf(byPeriod('morning', startPeriod: 1), d(9, 14))!,
        ],
        periodTimes: times(),
      );
      expect(cells.length, 3);
      expect(cells.map((x) => x.span.fromUid).toList(),
          ['morning', 'noon', 'evening']);
      expect(cells.map((x) => '${x.firstRow}-${x.lastRow}').toList(),
          ['1-1', '5-5', '11-13']);
      expect(cells.map((x) => x.rowSpan).toList(), [1, 1, 3]);
      expect(cells.map((x) => x.weekday).toSet().toList(), [3]);
    });

    test('★ 重叠时两条都保留，不自动重排（SPEC.md D10 的口径）', () {
      final c = cal();
      final cells = TimetableRowLayout.layoutUserEvents(
        weekday: 1,
        spans: [
          c.spanOf(byPeriod('long', startPeriod: 5, endPeriod: 6), d(9, 14))!,
          c.spanOf(byClock('short', from: '11:45', to: '12:20'), d(9, 14))!,
        ],
        periodTimes: times(),
      );
      expect(cells.length, 2, reason: '两条都要在，用户才看得出撞了');
      expect(cells.map((x) => x.span.fromUid).toList(), ['short', 'long'],
          reason: '同一行起点时结束行靠前的排前面');
      expect('${cells.first.firstRow}-${cells.first.lastRow}', '5-5');
      expect('${cells[1].firstRow}-${cells[1].lastRow}', '5-6');
    });

    test('空输入 → 空表', () {
      expect(
        TimetableRowLayout.layoutUserEvents(
            weekday: 1, spans: const [], periodTimes: times()),
        isEmpty,
      );
    });
  });

  test('rowCount 与课表行数一致（真实校历 15 节）', () {
    expect(TimetableRowLayout.rowCount, 15);
  });
}
