import 'dart:math';

import 'package:celechron/utils/tuple.dart';
import 'package:celechron/model/session.dart';
import 'package:celechron/model/semester.dart';
import 'package:celechron/design/custom_colors.dart';
import 'package:celechron/design/round_rectangle_card.dart';
import 'package:celechron/mod/user_event_periods.dart';
import 'package:celechron/mod/user_event_timetable.dart';
import 'package:celechron/page/scholar/course_schedule/course_card.dart';
import 'package:celechron/page/calendar/calendar_controller.dart';
import 'package:flutter/cupertino.dart';
import 'package:get/get.dart';

class ScheduleView extends StatelessWidget {
  final CalendarController controller;

  const ScheduleView({super.key, required this.controller});

  /// 课表画几行 = 校历里实际有几节。
  ///
  /// 2026-09-25 用户拍板：**从 13 行扩到 15 行**。原来的 13 是写死的，
  /// 而真实学期有 15 节（`assets/calendar/*.json` 的 `sessionTime`），
  /// 于是第 14、15 节（21:20 之后）的**课程与自定义日程都画不出来**。
  ///
  /// 以后校历再变，只改这一个常量（以及 [TimetableRowLayout.rowCount]）
  /// 和下面那张时间表 —— 别再散落写死行数。
  static const int _rowCount = 15;

  /// 每一节的**上课时刻**（左侧那一列显示的小字）。
  ///
  /// 取自校历 `sessionTime` 的原文，与上面 [TimetableRowLayout] 用的是同一份数据：
  /// 第 1 节 08:00、第 5 节 11:40 之后是午饭（第 6 节 13:25）、
  /// 第 10 节 17:05 之后是晚饭（第 11 节 18:50）、第 15 节 22:10 开始。
  static const List<String> _courseStartTime = [
    "08:00", // 1
    "08:50", // 2
    "10:00", // 3
    "10:50", // 4
    "11:40", // 5
    "13:25", // 6
    "14:15", // 7
    "15:05", // 8
    "16:15", // 9
    "17:05", // 10
    "18:50", // 11
    "19:40", // 12
    "20:30", // 13
    "21:20", // 14
    "22:10", // 15
  ];

  Widget _courseSchedule(BuildContext context, double gridHeight) {
    return RoundRectangleCard(
      child: Column(
        children: [
          Row(
            children: [
              const Spacer(flex: 1),
              Expanded(
                flex: 2,
                child: Center(
                  child: Text(
                    '一',
                    style:
                        CupertinoTheme.of(context).textTheme.textStyle.copyWith(
                              fontSize: 14,
                            ),
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: Center(
                  child: Text(
                    '二',
                    style:
                        CupertinoTheme.of(context).textTheme.textStyle.copyWith(
                              fontSize: 14,
                            ),
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: Center(
                  child: Text(
                    '三',
                    style:
                        CupertinoTheme.of(context).textTheme.textStyle.copyWith(
                              fontSize: 14,
                            ),
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: Center(
                  child: Text(
                    '四',
                    style:
                        CupertinoTheme.of(context).textTheme.textStyle.copyWith(
                              fontSize: 14,
                            ),
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: Center(
                  child: Text(
                    '五',
                    style:
                        CupertinoTheme.of(context).textTheme.textStyle.copyWith(
                              fontSize: 14,
                            ),
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: Center(
                  child: Text(
                    '六',
                    style:
                        CupertinoTheme.of(context).textTheme.textStyle.copyWith(
                              fontSize: 14,
                            ),
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: Center(
                  child: Text(
                    '日',
                    style:
                        CupertinoTheme.of(context).textTheme.textStyle.copyWith(
                              fontSize: 14,
                            ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          SizedBox(
            // 高度由可用空间算出来（见 build 里的 LayoutBuilder），
            // 不再写死 560：写死会在矮屏上被底部栏挡住半截，在高屏上又留一大块空白。
            height: gridHeight,
            child: Obx(
              () {
                // 开学前也把新学期课表显示出来，只是加一句提示；
                // 完全没数据时才是真的不在学期内。
                final semester = controller.getDisplayedSemester();
                if (semester == null) {
                  return Center(
                    child: Text(
                      '当前不在学期内',
                      style: CupertinoTheme.of(context)
                          .textTheme
                          .textStyle
                          .copyWith(fontSize: 16),
                    ),
                  );
                }
                if (controller.isBeforeSemester(semester)) {
                  final start = semester.firstDay;
                  return Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 6, 4, 2),
                        child: Text(
                          '新学期 ${start.month} 月 ${start.day} 日开始，'
                          '下面是它的课表',
                          textAlign: TextAlign.center,
                          style: CupertinoTheme.of(context)
                              .textTheme
                              .textStyle
                              .copyWith(
                                fontSize: 13,
                                color: CupertinoColors.systemOrange,
                              ),
                        ),
                      ),
                      Expanded(child: _timetable(context, semester)),
                    ],
                  );
                }

                return _timetable(context, semester);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _timetable(BuildContext context, Semester semester) {
    final isFirstHalf = controller.isFirstHalfSemester(semester);
    final sessionsByDayOfWeek = isFirstHalf
        ? semester.firstHalfTimetable
        : semester.secondHalfTimetable;

    return Row(
      children: [
        Expanded(
          flex: 1,
          child: Column(
            children: [
              for (var i = 1; i <= _rowCount; i++)
                Expanded(
                  child: Center(
                    child: Column(
                      children: [
                        FittedBox(
                          fit: BoxFit.fitWidth,
                          child: Text(
                            _courseStartTime[i - 1],
                            style: CupertinoTheme.of(context)
                                .textTheme
                                .textStyle
                                .copyWith(
                                  fontSize: 10,
                                ),
                          ),
                        ),
                        const SizedBox(
                          height: 2,
                        ),
                        Text(
                          i.toString(),
                          style: CupertinoTheme.of(context)
                              .textTheme
                              .textStyle
                              .copyWith(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        for (var i = 1; i <= 6; i++)
          Expanded(
            flex: 2,
            child: LayoutBuilder(
              builder: (context, constraints) => Stack(
                children: [
                  Column(
                    children: [
                      for (var j = 1; j <= 12; j++)
                        Expanded(
                          child: Container(),
                        ),
                      Expanded(
                        child: Container(),
                      ),
                    ],
                  ),
                  ..._buildCourseScheduleByDayOfWeek(
                      sessionsByDayOfWeek, i, constraints),
                  ..._buildUserEventsByDayOfWeek(
                      context, semester, i, constraints),
                ],
              ),
            ),
          ),
        Expanded(
          flex: 2,
          child: LayoutBuilder(
            builder: (context, constraints) => Stack(
              children: [
                Column(
                  children: [
                    for (var j = 1; j <= 12; j++)
                      Expanded(
                        child: Container(),
                      ),
                    Expanded(child: Container())
                  ],
                ),
                ..._buildCourseScheduleByDayOfWeek(
                    sessionsByDayOfWeek, 7, constraints),
                ..._buildUserEventsByDayOfWeek(context, semester, 7, constraints),
              ],
            ),
          ),
        )
      ],
    );
  }

  /// ===== MOD 2026-09-25：自定义日程画进课表格子（SPEC.md 步 5）=====
  ///
  /// 与课程**同一层 Stack**、同一套坐标（`(行号 - 1) / _rowCount`），因为位置计算
  /// 已经抽到 `TimetableRowLayout` 里（有单测），这里只负责画。
  ///
  /// 两个刻意的视觉决定：
  /// 1. **不等行重排**：两条日程撞在同一行就叠着画、各占一半宽度，
  ///    不清空、不挪动时间 —— SPEC.md D10 的口径是"叠加显示 + 角标"；
  /// 2. **固定粉 `#FFA6C9`**：课程走时段色阶（按小时从红变到紫），
  ///    自定义日程一律固定粉，两类不共用调色板（SPEC.md R3）。
  List<Widget> _buildUserEventsByDayOfWeek(
    BuildContext context,
    Semester semester,
    int day,
    BoxConstraints constraints,
  ) {
    final spans = controller.userEventSpansForWeekday(semester, day);
    if (spans.isEmpty) return const <Widget>[];

    final cells = TimetableRowLayout.layoutUserEvents(
      weekday: day,
      spans: spans,
      periodTimes: semester.periodTimes,
    );

    // 同一行区间里有几条（用来横向等分，避免互相完全盖住）
    final groupSize = <String, int>{};
    for (final cell in cells) {
      final key = '${cell.firstRow}-${cell.lastRow}';
      groupSize[key] = (groupSize[key] ?? 0) + 1;
    }
    final seen = <String, int>{};

    return cells.map((cell) {
      final key = '${cell.firstRow}-${cell.lastRow}';
      final total = groupSize[key] ?? 1;
      final index = seen[key] = (seen[key] ?? 0) + 1;
      final leftFactor = (index - 1) / total;
      final widthFactor = 1 / total;
      final conflicts =
          controller.userEventConflictsWithLecture(semester, cell.span);

      // 同一行区间里有几条时**并排**画：相对矩形直接按比例算出左右偏置，
      // 比套一层 Align + FractionalTranslation 少两层、也不会算错偏移。
      final top = (cell.firstRow - 1) * constraints.maxHeight / _rowCount;
      final bottom = (_rowCount - cell.lastRow) * constraints.maxHeight / _rowCount;
      return Positioned.fromRelativeRect(
        rect: RelativeRect.fromLTRB(
          leftFactor,
          top,
          1 - (leftFactor + widthFactor),
          bottom,
        ),
        child: _userEventCard(context, cell.span, conflicts),
      );
    }).toList();
  }

  /// 课表格子里那一条自定义日程
  Widget _userEventCard(BuildContext context, EventSpan span, bool conflicts) {
    // 固定粉（SPEC.md R3）；文字色用 UidColors 保证对比度，也让人一眼分清哪条是哪条
    const fill = Color(UserEventCalendar.eventColorArgb);
    final textColor = UidColors.colorFromUid(span.fromUid);
    return Container(
      margin: const EdgeInsets.all(1),
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
      decoration: BoxDecoration(
        color: fill.withValues(alpha: conflicts ? 1.0 : 0.85),
        borderRadius: BorderRadius.circular(4),
        border: conflicts
            ? Border.all(color: CupertinoColors.systemOrange, width: 1.2)
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  span.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 9,
                    height: 1.1,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                  ),
                ),
              ),
              // 与课冲突时的角标：说清"这条撞课了"，但不自动挪时间
              if (conflicts)
                const Icon(CupertinoIcons.exclamationmark_triangle_fill,
                    size: 8, color: CupertinoColors.systemOrange),
            ],
          ),
          if (span.location.isNotEmpty)
            Text(
              span.location,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 8, color: textColor),
            ),
        ],
      ),
    );
  }

  List<Widget> _buildCourseScheduleByDayOfWeek(
      List<List<Session>> sessionsByDayOfWeek,
      int day,
      BoxConstraints constraints) {
    List<Tuple<int, int>> period = [];
    for (var i = 1; i <= _rowCount; i++) {
      period.add(Tuple(i, i));
    }
    for (var s in sessionsByDayOfWeek[day]) {
      int sl = s.time.first, sr = s.time.last;
      int xl = sl, xr = sr;
      for (var i in period) {
        if (!(i.item2 < sl || sr < i.item1)) {
          xl = min(xl, i.item1);
          xr = max(xr, i.item2);
        }
      }
      period.removeWhere((x) => xl <= x.item1 && x.item2 <= xr);
      period.add(Tuple(xl, xr));
    }
    List<List<Session>> sessionList = [];
    for (var _ in period) {
      sessionList.add([]);
    }
    for (var s in sessionsByDayOfWeek[day]) {
      int sl = s.time.first, sr = s.time.last;
      for (int i = 0; i < period.length; i++) {
        if (!(period[i].item2 < sl || sr < period[i].item1)) {
          bool added = false;
          for (var t in sessionList[i]) {
            if (t.id == s.id) {
              added = true;
              Set<int> timeSet = Set.from(t.time);
              timeSet.addAll(s.time);
              t.time = List.from(timeSet);
              t.time.sort();
              break;
            }
          }
          if (!added) {
            sessionList[i].add(Session.fromJson(s.toJson()));
          }
        }
      }
    }

    List<Widget> cardList = [];
    for (int i = 0; i < period.length; i++) {
      if (sessionList[i].isNotEmpty) {
        cardList.add(
          Positioned.fromRelativeRect(
            rect: RelativeRect.fromLTRB(
              0,
              (period[i].item1 - 1) * constraints.maxHeight / _rowCount,
              0,
              (_rowCount - period[i].item2) * constraints.maxHeight / _rowCount,
            ),
            child: SessionCard(
              sessionList: sessionList[i],
              hideInfomation: false,
            ),
          ),
        );
      }
    }

    return cardList;
  }

  @override
  Widget build(BuildContext context) {
    // 课表要一屏看全：把网格高度算成可用高度减去留白，
    // 而不是写死一个值， 写死的值在矮屏上会被底部栏挡住下半截。
    return LayoutBuilder(
      builder: (context, constraints) {
        // 上下各 16 的页面留白 + 卡片内边距 + 星期表头 ≈ 88
        const chrome = 88.0;
        // 太矮时给一个下限，宁可能滚动也不要挤成一条缝。
        // 2026-09-25 从 380 提到 460：**行数从 13 变成 15** 之后，
        // 380 分给 15 行只有 25px/行（原来是 29px），卡片里的字会挤到看不清。
        // 460 是"每行约 31px"的下限；矮屏上由外面那层 SingleChildScrollView 兜住。
        final available = constraints.maxHeight - chrome;
        final gridHeight = available.clamp(460.0, 960.0);

        return SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: _courseSchedule(context, gridHeight),
          ),
        );
      },
    );
  }
}
