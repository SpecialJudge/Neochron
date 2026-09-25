import 'package:celechron/http/calendar_bundled_config.dart';
import 'package:celechron/http/calendar_config_parser.dart';
import 'package:celechron/model/semester.dart';
import 'package:celechron/mod/user_event.dart';
import 'package:celechron/mod/user_event_periods.dart';
import 'package:celechron/mod/user_event_timetable.dart';
import 'package:celechron/page/calendar/calendar_controller.dart';
import 'package:flutter_test/flutter_test.dart';

/// ============ 用**真校历 + 你真机上那条日程**把课表这条路整段跑一遍 ============
///
/// 背景：你在真机上两次都没看见粉色卡片。前面那些测试用的都是我手工搭的
/// 15 节表和手工造的 `Semester`，**没有一次是用真校历资源跑的**，
/// 所以"测试全绿"并不能排除"真数据下不成立"。这个文件补的就是这一步。
///
/// 数据全部照抄你导出里那条（`celechron-backup-20260925-154943.json`）：
/// 学生会例会 / startDate 2026-09-25（周五）/ 每周 / 截止 2027-01-03 /
/// 19:00-20:30 / semesterName `2026-2027秋冬`。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<Semester> realSemester() async {
    final text = (await BundledCalendarConfig.load('2026-2027-1'))!;
    final config = decodeAndValidateCalendarConfig(text, context: '内置校历');
    return Semester('2026-2027秋冬')..addZjuCalendar(config);
  }

  UserEvent realEvent() => UserEvent(
        uid: 'evt-hmm6ttjaf9-3-egl6si',
        title: '学生会例会',
        startDate: DateTime(2026, 9, 25),
        dayOfWeek: 5, // 构造函数会按 startDate 纠正，这里故意写对
        startClock: '19:00',
        endClock: '20:30',
        repeatPeriod: 1,
        repeatUntil: DateTime(2027, 1, 3),
        semesterName: '2026-2027秋冬',
        color: 0xFF66CCFF,
        createdAt: DateTime(2026, 9, 25, 15, 49, 30),
        updatedAt: DateTime(2026, 9, 25, 15, 49, 30),
      );

  group('真校历下的那条例会', () {
    test('学期起止日与校历一致（9/14 开学、次年 1/3 结束）', () async {
      final semester = await realSemester();
      expect(semester.hasCalendar, isTrue);
      expect(semester.name, '2026-2027秋冬');
      expect(semester.firstDay, DateTime(2026, 9, 14));
      expect(semester.lastDay, DateTime(2027, 1, 3));
      expect(semester.periodTimes.length, 16);
    });

    test('锚点 = 9/25（学期第一个周五是 9/18，要往后推到它自己的起始日）', () async {
      final semester = await realSemester();
      expect(
        CalendarController.anchorDateFor(realEvent(), semester, 5),
        DateTime(2026, 9, 25),
      );
    });

    test('展开成时段：9/25 那天有一条', () async {
      final semester = await realSemester();
      final calendar = UserEventCalendar(
        semesterName: semester.name,
        firstDay: semester.firstDay,
        lastDay: semester.lastDay,
        periodTimes: semester.periodTimes,
      );
      final anchor = CalendarController.anchorDateFor(realEvent(), semester, 5)!;
      final spans = calendar.spansBetween([realEvent()], anchor, anchor);
      expect(spans.length, 1, reason: '锚点那天必须铺出一条时段，否则课表格子空着');
      expect(spans.single.fromUid, 'evt-hmm6ttjaf9-3-egl6si');
      expect(spans.single.start, DateTime(2026, 9, 25, 19, 0));
      expect(spans.single.end, DateTime(2026, 9, 25, 20, 30));
    });

    test('★ 落到课表的第 11-13 行（周五那一列）', () async {
      final semester = await realSemester();
      final calendar = UserEventCalendar(
        semesterName: semester.name,
        firstDay: semester.firstDay,
        lastDay: semester.lastDay,
        periodTimes: semester.periodTimes,
      );
      final anchor = CalendarController.anchorDateFor(realEvent(), semester, 5)!;
      final spans = calendar.spansBetween([realEvent()], anchor, anchor);
      final cells = TimetableRowLayout.layoutUserEvents(
        weekday: 5,
        spans: spans,
        periodTimes: semester.periodTimes,
      );
      expect(cells.length, 1);
      expect(cells.single.weekday, 5);
      expect(cells.single.firstRow, 11);
      expect(cells.single.lastRow, 13);
      // 行号必须落在课表真的画得出来的范围内
      expect(cells.single.firstRow, greaterThanOrEqualTo(1));
      expect(cells.single.lastRow, lessThanOrEqualTo(TimetableRowLayout.rowCount));
    });

    test('学期名对得上（对不上就会被学期过滤掉，一条都不画）', () async {
      final semester = await realSemester();
      expect(semester.name, '2026-2027秋冬');
      // 与 `userEventSpansForWeekday` 的过滤口径一致：没写学期（null）算"不限学期"，
      // 写了就必须与本学期的名字相等。`Semester.name` 是非空的，所以只判前者。
      expect(realEvent().semesterName ?? semester.name, semester.name);
    });
  });
}
