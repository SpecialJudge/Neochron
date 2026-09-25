import 'package:celechron/mod/user_event.dart';
import 'package:celechron/mod/user_event_date.dart';
import 'package:celechron/mod/user_event_rule.dart';
import 'package:celechron/model/period.dart';

/// ============ 自定义日程 -> 可显示的时段 ============
///
/// 这一层只做一件事：把「每两周的周一第 5-6 节」这种**规则**
/// 展开成一个个**具体日期 + 具体钟点**的时段，好让日历与课表去画。
///
/// ============ 为什么分成「纯逻辑 + 薄转换」两块 ============
///
/// [UserEventCalendar] 只做计算，产出自己的轻量类型 [EventSpan]；
/// 把 [EventSpan] 变成真的 `Period` 是最后那两个函数干的事。
/// 这么分只有一个理由：**`Period` 会把 Flutter 拖进来**
/// （`period.dart` -> `time_helper.dart` -> `utils.dart` -> `flutter_secure_storage`），
/// 一旦在计算里直接用 `Period`，这段最容易算错的东西
/// （节次↔钟点换算、发生日筛选、冲突判定）就再也没法脱离 Flutter 环境验证了。
/// 拆开之后，"算得对不对"可以单独跑，"造出来的对象对不对"一眼就能看出来。
///
/// 这与 `user_event_date.dart` 顶部那段是同一个考虑。
///
/// ============ 为什么不直接吃 `Semester` ============
///
/// `Semester` 是教务数据的容器（Hive 适配器、几百行合并逻辑都在里面），
/// 而这里只需要三样：学期起止日、节次到钟点的换算表、已有课程占用的时间。
/// 所以入参是一个轻量快照 [UserEventCalendar]：调用方负责把真 `Semester` 拍成快照，
/// 口径只有一处，本文件也就能被单测随意构造。
///
/// ============ 颜色（SPEC.md R3）============
///
/// 课表格子里的课程走**时段色阶**（`TimeColors.colorFromHour`，按小时变色），
/// 自定义日程**一律用固定粉**（[UserEventCalendar.eventColorArgb]）。
/// 两类不共用调色板，否则 20 点的例会（品红档）与 8 点的课（红档）会撞色。
class UserEventCalendar {
  /// 学期的显示名（`Semester.name`），只用于界面上的归属说明
  final String semesterName;

  /// 学期第一天 / 最后一天（含）。用来算扩展范围，以及筛掉不在学期内的日期
  final DateTime firstDay;
  final DateTime lastDay;

  /// 第几节 => 那节课的起止偏移量（下标即节次，`[0]` 空着不用）。
  /// 直接来自 `Semester.periodTimes`。
  final List<List<Duration>> periodTimes;

  /// 已有课程占用的时间（用来判断冲突）。可以只给关心的那几天，给多了也不影响。
  final List<LectureTime> lectures;

  /// 自定义日程的固定色（爱莉粉 `#FFA6C9`，SPEC.md R3）
  static const int eventColorArgb = 0xFFFFA6C9;

  const UserEventCalendar({
    required this.semesterName,
    required this.firstDay,
    required this.lastDay,
    required this.periodTimes,
    this.lectures = const <LectureTime>[],
  });

  /// 一条日程在 [day] 那天的时段；那天不发生、或换算不出来就返回 null。
  EventSpan? spanOf(UserEvent event, DateTime day) {
    if (!UserEventRule.occursOn(event, day)) return null;
    final start = startAt(event, day);
    final end = endAt(event, day);
    if (start == null || end == null) return null;
    // 结束早于开始时按"单时刻"处理：一个点，不画成负长度
    final safeEnd = end.isBefore(start) ? start : end;
    return EventSpan(
      uid: occurrenceUid(event, day),
      fromUid: event.uid,
      title: event.title,
      note: event.note,
      location: event.location,
      start: start,
      end: safeEnd,
      day: userEventDateOnly(day),
    );
  }

  /// 这条日程在那天的开始钟点；换算不出来返回 null
  DateTime? startAt(UserEvent event, DateTime day) {
    final offset = _startOffsetOf(event);
    if (offset == null) return null;
    return userEventDateOnly(day).add(offset);
  }

  /// 这条日程在那天的结束钟点；换算不出来返回 null
  DateTime? endAt(UserEvent event, DateTime day) {
    final offset = _endOffsetOf(event);
    if (offset == null) return null;
    return userEventDateOnly(day).add(offset);
  }

  Duration? _startOffsetOf(UserEvent event) {
    if (!event.usesPeriod) {
      final hm = parseClock(event.startClock);
      if (hm == null) return null;
      return Duration(hours: hm.$1, minutes: hm.$2);
    }
    return _offsetOfPeriod(event.startPeriod!);
  }

  Duration? _endOffsetOf(UserEvent event) {
    if (!event.usesPeriod) {
      final hm = parseClock(event.endClock ?? event.startClock);
      if (hm == null) return null;
      return Duration(hours: hm.$1, minutes: hm.$2);
    }
    return _offsetOfPeriod(event.endPeriod ?? event.startPeriod!, last: true);
  }

  /// 第 n 节 -> 偏移量。表里没有这一节就返回 null（**不猜**）。
  Duration? _offsetOfPeriod(int index, {bool last = false}) {
    if (index < 0 || index >= periodTimes.length) return null;
    final slot = periodTimes[index];
    if (slot.isEmpty) return null;
    return last ? slot.last : slot.first;
  }

  /// 某一次的稳定 uid：`<日程uid>@<yyyyMMdd>`。
  ///
  /// 稳定很重要：同一天问两次必须得到同一个字符串，
  /// 否则列表重建时会被当成两条不同的日程（会闪、会重复）。
  static String occurrenceUid(UserEvent event, DateTime day) {
    final d = userEventDateOnly(day);
    final month = d.month.toString().padLeft(2, '0');
    final dayOfMonth = d.day.toString().padLeft(2, '0');
    return '${event.uid}@${d.year}$month$dayOfMonth';
  }

  /// 一条日程在 [from] 到 [to] 之间（含两端）会发生的所有日期。
  ///
  /// 把"发生判定"（[UserEventRule]）的活直接转过去，这里只补一层学期边界：
  /// 超出学期范围的日子不铺（课表按学期画，超出去也没地方放）。
  List<DateTime> daysOf(
    UserEvent event,
    DateTime from,
    DateTime to, {
    bool clampToSemester = true,
  }) {
    var start = userEventDateOnly(from);
    var end = userEventDateOnly(to);
    if (clampToSemester) {
      final semesterStart = userEventDateOnly(firstDay);
      final semesterEnd = userEventDateOnly(lastDay);
      if (start.isBefore(semesterStart)) start = semesterStart;
      if (end.isAfter(semesterEnd)) end = semesterEnd;
    }
    if (end.isBefore(start)) return const <DateTime>[];
    return UserEventRule.occurrencesBetween(event, start, end);
  }

  /// 多条日程在 [from] 到 [to] 之间的全部时段，按开始时间升序。
  ///
  /// 这就是"日历当天列表"要的东西：拿它和课程时段拼一起就能画。
  List<EventSpan> spansBetween(
    Iterable<UserEvent> events,
    DateTime from,
    DateTime to, {
    bool clampToSemester = true,
  }) {
    final result = <EventSpan>[];
    for (final event in events) {
      for (final day
          in daysOf(event, from, to, clampToSemester: clampToSemester)) {
        final span = spanOf(event, day);
        if (span != null) result.add(span);
      }
    }
    result.sort(compareSpan);
    return result;
  }

  /// 某一天的全部时段（含已结束的；要不要滤掉由界面决定）
  List<EventSpan> spansOfDay(Iterable<UserEvent> events, DateTime day) =>
      spansBetween(events, day, day);

  /// 这个时段是不是和某节课撞了。
  ///
  /// 判定口径是"两个区间有交集"：`aStart < bEnd && bStart < aEnd`。
  /// 用 `<` 而不是 `<=`：一节课 09:35 下课、日程 09:35 开始**不算冲突**，
  /// 否则每个"接着上课"的日程都会一直飘着冲突角标，用户很快就不看它了。
  bool conflictsWithLecture(EventSpan span) {
    for (final lecture in lectures) {
      if (span.start.isBefore(lecture.end) &&
          lecture.start.isBefore(span.end)) {
        return true;
      }
    }
    return false;
  }

  /// 从一堆时段里挑出与课程冲突的那些（SPEC.md D10：叠加显示 + 角标）
  List<EventSpan> conflictsOf(Iterable<EventSpan> spans) =>
      spans.where(conflictsWithLecture).toList();

  /// `"19:00"` / `"19:00:00"` -> `(19, 0)`；读不出来返回 null
  static (int, int)? parseClock(String? clock) {
    if (clock == null) return null;
    final text = clock.trim();
    if (text.isEmpty) return null;
    final parts = text.split(':');
    if (parts.length < 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
    return (hour, minute);
  }
}

/// 自定义日程某一次的时段（**不依赖 Flutter 的轻量类型**）。
///
/// 为什么不直接用 `Period`：见本文件顶部"为什么分成两块"。
/// 要落成界面能画的对象时用 [toPeriod] / [toPeriods]。
class EventSpan {
  /// 某一次的唯一键：`<日程uid>@<yyyyMMdd>`
  final String uid;

  /// 原始日程的 uid（点卡片时据此找回 [UserEvent]）
  final String fromUid;

  final String title;
  final String note;
  final String location;

  final DateTime start;
  final DateTime end;

  /// 这一天的 00:00（方便按天分组）
  final DateTime day;

  const EventSpan({
    required this.uid,
    required this.fromUid,
    required this.title,
    required this.note,
    required this.location,
    required this.start,
    required this.end,
    required this.day,
  });

  Duration get duration => end.difference(start);

  /// 是不是一整天里已经过去的时段
  bool get hasEnded => end.isBefore(DateTime.now());

  @override
  String toString() => 'EventSpan($title @ $start~$end)';
}

/// 一节课占用的时间（只留判定冲突需要的两个端点）
class LectureTime {
  final DateTime start;
  final DateTime end;

  const LectureTime(this.start, this.end);

  /// 从 `Period` 造一条（课程的 `period.type == PeriodType.classes`）
  factory LectureTime.ofPeriod(Period period) =>
      LectureTime(period.startTime, period.endTime);
}

/// 时段按开始时间升序；同时开始时结束早的在前
int compareSpan(EventSpan a, EventSpan b) {
  final byStart = a.start.compareTo(b.start);
  if (byStart != 0) return byStart;
  return a.end.compareTo(b.end);
}

// ------------------------------------------------------------ 到 `Period` 的薄转换
//
// 只有这两个函数会碰到 `Period`（因而会间接碰到 Flutter）。
// 逻辑为零：字段一一对应，`type` 一律是 `PeriodType.user`。

/// 把一个时段变成日历能画的 `Period`
Period toPeriod(EventSpan span) => Period(
      uid: span.uid,
      fromUid: span.fromUid,
      type: PeriodType.user,
      description: span.note,
      startTime: span.start,
      endTime: span.end,
      location: span.location,
      summary: span.title,
    );

/// 批量转换
List<Period> toPeriods(Iterable<EventSpan> spans) =>
    spans.map(toPeriod).toList();
