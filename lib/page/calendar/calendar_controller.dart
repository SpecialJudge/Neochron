import 'dart:async';
import 'package:celechron/database/database_helper.dart';
import 'package:celechron/model/task.dart';
import 'package:celechron/mod/calendar_fold.dart';
import 'package:celechron/mod/calendar_paging.dart';
import 'package:celechron/mod/user_event.dart';
import 'package:celechron/mod/user_event_periods.dart';
import 'package:celechron/mod/user_event_store.dart';
import 'package:celechron/utils/utils.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:celechron/model/period.dart';
import 'package:celechron/model/scholar.dart';
import 'package:celechron/model/semester.dart';

enum CalendarViewMode {
  calendar,
  schedule,

  /// 接下来：课程/考试/日程按开始时间、非备忘待办按提醒时间排序
  upcoming,
}

/// [day] 落在 [semesters] 里的哪个学期；哪个都不在就 `null`。
///
/// ===== MOD: 给自定义日程用（2026-09-25）=====
///
/// 抽成顶层纯函数有两个原因：
/// 1. `CalendarController.getSemesterOf` 要按"用户翻到的那一天"找学期，
///    与校历归属是同一个口径，写在两处迟早不一致；
/// 2. 它只依赖 `Semester` 的几个 getter，能直接单测（不必启动 Hive 或整个页面）。
///
/// ⚠️ **必须要求 `hasCalendar`**：没套过校历的学期，`firstDay` / `lastDay`
/// 返回的是"求值那一刻的现在"这种占位值，拿它判断会把任意一天都算进去。
/// 这个坑 `getUpcomingSemester` 的注释里已经记过一次。
Semester? semesterContaining(Iterable<Semester> semesters, DateTime day) {
  final target = DateTime(day.year, day.month, day.day);
  for (final semester in semesters) {
    if (!semester.hasCalendar) continue;
    final first = semester.firstDay;
    final last = semester.lastDay;
    final from = DateTime(first.year, first.month, first.day);
    final to = DateTime(last.year, last.month, last.day);
    if (target.isBefore(from) || target.isAfter(to)) continue;
    return semester;
  }
  return null;
}

class CalendarController extends GetxController {
  final selectedDay = DateTime.now().obs;
  final focusedDay = DateTime.now().obs;
  final calendarFormat = CalendarFormat.month.obs;
  final events = <DateTime, List<Period>>{}.obs;
  final scholar = Get.find<Rx<Scholar>>(tag: 'scholar');
  final taskList = Get.find<RxList<Task>>(tag: 'taskList');

  /// ===== MOD: 自定义日程（学生组织例会那种，SPEC.md 步 3）=====
  ///
  /// 用户自己排的日程。**刻意与课程分开存**：课程由教务刷新重建，
  /// 用户数据混进 `Scholar` 或 `Semester` 里迟早被冲掉（见 `user_event_store.dart`）。
  /// 这里只放"读出来的一份快照"，增删改由日程页自己再调 [loadUserEvents] 刷新。
  final userEvents = <UserEvent>[].obs;


  /// 默认进接下来（用户要求：打开日程页先看接下来要做什么）
  final viewMode = CalendarViewMode.upcoming.obs;

  static List<String> numToChinese = ['一', '二', '三', '四', '五', '六', '七', '八'];

  String dayDescription(DateTime day) {
    var semester = scholar.value.semesters.firstWhereOrNull(
        (e) => !day.isBefore(e.firstDay) && !day.isAfter(e.lastDay));
    if (semester == null) return '考试周/假期';

    var toFirstWeek = day.difference(semester.firstDay).inDays ~/ 7;
    if (toFirstWeek < 8) {
      return '${semester.name[9]}${numToChinese[toFirstWeek]}周';
    }
    var toLastWeek = 7 - semester.lastDay.difference(day).inDays ~/ 7;
    if (toLastWeek < 8) {
      return '${semester.name[10]}${numToChinese[toLastWeek]}周';
    }
    return '考试周/假期';
  }

  /// 接下来的**心跳**：定时跳一下，让倒计时与排序不会停在旧值。
  ///
  /// 背景：这一页原先没有任何定时器，`还有 N 分钟` 只在"页面碰巧重建"时才算一次。
  /// 实测出现过状态栏已经 13:16、卡片还写着还有 24 分钟（那是 13:01 的旧值）。
  /// 现在每 20 秒跳一次（只在看接下来时跳，课表/日历没有倒计时，不必跟着重建）。
  final upcomingTick = 0.obs;
  Timer? _tickTimer;

  @override
  void onInit() {
    loadUserEvents();
    refreshEvents();
    ever(scholar, (callback) => refreshEvents());
    // 自定义日程变了就重算日历标记（增删改都走这条，界面不用自己记得刷新）
    ever(userEvents, (callback) => refreshEvents());
    _tickTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (viewMode.value == CalendarViewMode.upcoming) {
        upcomingTick.value++;
      }
    });
    // ===== MOD ===== 进日历这一面时恢复整月
    //
    // 上滑收起日历是一次性的浏览动作，不该**粘着**不走：用户翻去接下来
    // 再翻回来，如果只剩一行星期，很容易以为月视图坏了， 而展开的手势
    // （回到列表顶部继续下拉）不是一眼能看出来的。所以每次进这一面都从整月开始。
    ever(viewMode, (mode) {
      if (mode == CalendarViewMode.calendar) {
        calendarFormat.value = CalendarFormat.month;
      }
    });
    super.onInit();
  }

  @override
  void onClose() {
    _tickTimer?.cancel();
    _tickTimer = null;
    super.onClose();
  }

  void refreshEvents() {
    events.clear();
    Set<DateTime> keySet = {};
    for (var element in Get.find<Rx<Scholar>>(tag: 'scholar').value.periods) {
      DateTime chop = chopDate(element.startTime);
      if (events[chop] == null) events[chop] = <Period>[];
      events[chop]!.add(element);
      keySet.add(chop);
    }
    for (var i in keySet) {
      events[i]!.sort((a, b) => a.startTime.compareTo(b.startTime));
    }
  }

  DateTime chopDate(DateTime day) {
    return DateTime(day.year, day.month, day.day);
  }

  // ===== MOD: 自定义日程（SPEC.md 步 3）=====

  /// 从本地库读一份自定义日程快照。
  ///
  /// **读不出来就留空表**，绝不阻塞日程页：数据库没准备好（启动早期）或者
  /// 盒子打不开时，用户看到的应该是"只有课程"的日历，而不是一个崩掉的页面。
  void loadUserEvents() {
    try {
      final db = Get.find<DatabaseHelper>(tag: 'db');
      userEvents.value = db.userEvents();
      // 顺手清一次过期墓碑（默认留 180 天）。放在这里而不是启动早期：
      // 日程页建起来就说明数据库已经好了，而且这里本来就在碰日程相关的盒子。
      // 幂等、代价很小；不清的话墓碑会随删除次数无限长下去。
      unawaited(db.pruneUserEventTombstones());
    } catch (_) {
      userEvents.value = <UserEvent>[];
    }
  }

  /// 把某个学期拍成 [UserEventCalendar]（自定义日程要的那份轻量快照）。
  ///
  /// 两处口径都取自既有代码，没有自己另写一份：
  /// - 节次到钟点的换算表来自 `Semester.periodTimes`（与课程同一套）；
  /// - 课程占用时间来自 `Semester.periods` 里 type 为 `classes` 的那些，
  ///   用来判断"自定义日程与课冲突"（SPEC.md D10）。
  ///
  /// 故意**不把 `PeriodType.user` 算进课程**：那些正是用户自己的活动型待办，
  /// 把它们当成"课"会把自己的日程判成和自己冲突。
  UserEventCalendar userEventCalendarFor(Semester semester) {
    final periods = semester.periods;
    final lectures = <LectureTime>[];
    for (final period in periods) {
      if (period.type != PeriodType.classes) continue;
      lectures.add(LectureTime.ofPeriod(period));
    }
    return UserEventCalendar(
      semesterName: semester.name,
      firstDay: semester.firstDay,
      lastDay: semester.lastDay,
      periodTimes: semester.periodTimes,
      lectures: lectures,
    );
  }

  /// [day] 那天的自定义日程时段（转成日历能画的 `Period`）。
  ///
  /// 找不到学期（假期、考试周）时返回空表：那种时候课表也没有，
  /// 没有节次换算表可用，硬算只会把第 5 节画到错误的时间上。
  List<Period> userEventPeriodsOfDay(DateTime day) {
    final semester = getSemesterOf(day);
    if (semester == null) return const <Period>[];
    // 只铺**属于这个学期**的日程（外加没写学期的那种"不限学期"）。
    // 少了这一步，下学期建的例会会出现在本学期这一天的列表里，
    // 而且用的是本学期的节次时间 —— 更糟的是它没有对应的课表来对照。
    return toPeriods(userEventCalendarFor(semester)
        .spansOfDay(userEventsForSemester(semester.name), day));
  }

  /// 本地那份快照里，属于 [semesterName] 的日程（外加没写学期的）。
  ///
  /// 为什么不用 `DatabaseHelper.userEventsOfSemester`：那是 `DatabaseHelper`
  /// 上的扩展方法，控制器调不到；而且这里已经有一份 [userEvents] 快照在手，
  /// 就地筛比再读一次盒子便宜。
  List<UserEvent> userEventsForSemester(String? semesterName) => userEvents
      .where((event) =>
          event.semesterName == null ||
          semesterName == null ||
          event.semesterName == semesterName)
      .toList();

  /// [from] 到 [to] 之间（含两端）的自定义日程时段。
  ///
  /// 「接下来」那一面要跨天取（默认看未来 7 天），所以需要区间版本。
  /// 跨学期时会按天去各自学期里取，不会因为"这一天不在本学期"就整段漏掉。
  List<Period> userEventPeriodsBetween(DateTime from, DateTime to) {
    var day = chopDate(from);
    final last = chopDate(to);
    final result = <Period>[];
    while (!day.isAfter(last)) {
      result.addAll(userEventPeriodsOfDay(day));
      day = DateTime(day.year, day.month, day.day + 1);
    }
    return result;
  }

  /// 课表那面要的：某个星期几在 [semester] 里的自定义日程时段。
  ///
  /// 课表是**规则表**（周一到周日 × 13 节），所以要的是"这个星期几那一天长什么样"，
  /// 而不是"某个具体日期"。做法是拿该学期里**第一个**这个星期几的日期当代表
  /// （例如本学期的第一个周一），再用与日历完全相同的口径铺一次。
  ///
  /// 为什么这样可以：本功能的口径是**自然周几 + 间隔周数**（SPEC.md D3），
  /// 每 N 周才发生的那种在规则表上本来就画不出来 —— 课表只能表示"通常是哪几天"。
  /// 具体哪一周有没有，请看日历那面（那里是按真实日期铺的）。
  List<EventSpan> userEventSpansForWeekday(Semester semester, int weekday) {
    final anchor = firstDateOfWeekday(semester, weekday);
    if (anchor == null) return const <EventSpan>[];
    // 同上：只铺属于这个学期的（+ 不限学期的）。传全量的话，
    // 别的学期建的例会会出现在这张表上，位置还按本学期的节次算。
    return userEventCalendarFor(semester)
        .spansBetween(userEventsForSemester(semester.name), anchor, anchor);
  }

  /// 这个学期里第一个星期 [weekday] 的日期（例如本学期第一个周一）；没有则 null
  DateTime? firstDateOfWeekday(Semester semester, int weekday) {
    if (!semester.hasCalendar) return null;
    final first = chopDate(semester.firstDay);
    final last = chopDate(semester.lastDay);
    // 从学期第一天往后找同一天最多 7 天就能碰到
    for (var offset = 0; offset < 7; offset++) {
      final candidate = DateTime(first.year, first.month, first.day + offset);
      if (candidate.isAfter(last)) return null;
      if (candidate.weekday == weekday) return candidate;
    }
    return null;
  }

  /// 这个时段与课程撞了吗（课表格子上的角标用它，SPEC.md D10）
  bool userEventConflictsWithLecture(Semester semester, EventSpan span) =>
      userEventCalendarFor(semester).conflictsWithLecture(span);

  /// [day] 落在哪个学期（按学期起止日判断）；没有就 null。
  ///
  /// 与 [getCurrentSemester] 的区别：那个只看"今天"，这个看**任意一天**
  /// （用户会翻到别的日期去，日历得跟着那一天所处的学期来算）。
  Semester? getSemesterOf(DateTime day) => semesterContaining(
        scholar.value.semesters,
        day,
      );

  List<Period> getEventsForDay(DateTime day) {
    DateTime chop = chopDate(day);
    var eventsOfDay = <Period>[];
    if (events[chop] != null) {
      for (var event in events[chop]!) {
        eventsOfDay.add(event.copyWith());
      }
    }
    // ===== MOD: 自定义日程也进当天列表（SPEC.md 步 3）=====
    //
    // 与课程/考试同一层：它们都是 Period，界面一视同仁地画，
    // 靠 `type`（PeriodType.user）与固定粉区分（SPEC.md R3）。
    eventsOfDay.addAll(userEventPeriodsOfDay(day));
    for (var deadline in taskList) {
      // ===== 已完成的待办不在日程页露面（用户要求）=====
      if (deadline.status == TaskStatus.completed) continue;
      if (deadline.type == TaskType.fixed ||
          deadline.type == TaskType.fixedlegacy) {
        List<Period> periods = deadline.getPeriodOfDay(dateOnly(day));
        for (var p in periods) {
          eventsOfDay.add(p);
        }
      }
    }
    eventsOfDay.sort((a, b) => a.startTime.compareTo(b.startTime));
    return eventsOfDay;
  }

  /// 当天到期的待办：**截止型与提醒型**都进日历，备忘型不进（它没有时间）。
  ///
  /// 活动型（有起止）走的是 getEventsForDay 的 Period 分支，不在这里重复出现。
  /// **已完成的也不显示**， 日程页看的是还要做什么。
  List<Task> getDeadlinesForDay(DateTime day) {
    final target = dateOnly(day);
    final result = taskList
        .where((task) =>
            task.showsInCalendar &&
            !task.isEvent &&
            task.status != TaskStatus.deleted &&
            task.status != TaskStatus.completed &&
            dateOnly(task.endTime) == target)
        .toList();
    result.sort((a, b) => a.endTime.compareTo(b.endTime));
    return result;
  }

  /// 月视图上的标记：课程/考试/日程（Period）+ 当天到期的待办（Task）。
  List<Object> getMarkersForDay(DateTime day) {
    return <Object>[...getEventsForDay(day), ...getDeadlinesForDay(day)];
  }

  /// 进入课表之前是哪个面，用来原路返回。
  CalendarViewMode _beforeSchedule = CalendarViewMode.upcoming;

  /// 右上角那个按钮：在**课表**与进来之前那个面之间切换。
  ///
  /// 修的是一个实打实的方向错：原来是
  /// `viewMode == calendar ? schedule : calendar`，在接下来时落到 else，
  /// 于是点一下跳到**日历**，而用户点它是想看**课表**。
  ///
  /// 另外这里**不碰 [cardFace]**：翻转动画只属于接下来 ⇄ 日历这一对，
  /// 切课表本来就不该翻。
  /// 右上角那个按钮按下后的视图。**纯函数，便于回归测试。**
  ///
  /// 修的是一个实打实的方向错：原来是
  /// `viewMode == calendar ? schedule : calendar`，在接下来时落到 else，
  /// 于是点一下跳到**日历**，而用户点它是想看**课表**。
  /// 现在：不在课表 → 去课表；已在课表 → 回进来之前那个面。
  static CalendarViewMode toggledViewMode(
      CalendarViewMode current, CalendarViewMode beforeSchedule) {
    if (current == CalendarViewMode.schedule) return beforeSchedule;
    return CalendarViewMode.schedule;
  }

  void toggleViewMode() {
    final next = toggledViewMode(viewMode.value, _beforeSchedule);
    if (viewMode.value != CalendarViewMode.schedule) {
      _beforeSchedule = viewMode.value;
    }
    viewMode.value = next;
  }

  /// 当前是不是在看课表（右上角按钮的图标据此切换）。
  bool get isScheduleMode => viewMode.value == CalendarViewMode.schedule;

  /// 顶部那个空心圆：在接下来与日历之间翻转
  void toggleUpcoming() {
    if (viewMode.value == CalendarViewMode.upcoming) {
      viewMode.value = CalendarViewMode.calendar;
      cardFace.value = 'calendar';
    } else {
      viewMode.value = CalendarViewMode.upcoming;
      cardFace.value = 'upcoming';
    }
  }

  /// 横向翻页：`-1` 上一页、`+1` 下一页。
  ///
  /// 月视图按整月挪、周视图按整周挪；日期按目标月长度收口（见 [shiftedFocusedDay]）。
  void shiftFocused(int direction) {
    focusedDay.value =
        shiftedFocusedDay(focusedDay.value, calendarFormat.value, direction);
  }

  /// 折叠／展开日历（日历下面那个小提示点的就是它）。
  void setCalendarFormat(CalendarFormat format) {
    if (calendarFormat.value != format) calendarFormat.value = format;
  }

  /// 卡片翻转的正反面。
  ///
  /// **只有接下来 ⇄ 日历这一对切换才算换面**， 右上角那个按钮切到课表
  /// 不换面，所以不会播放翻转动画（用户反馈过：切课表也翻一下很突兀）。
  final cardFace = 'upcoming'.obs;

  // ===== MOD ===== 日程页上滑收起日历（用户要求：上滑折成一周，滑回顶部展开）

  /// 折叠手势的累加器。判定口径全在 `lib/mod/calendar_fold.dart`（纯逻辑，有单测）。
  final foldGesture = CalendarFoldGesture();

  /// 接在当天那条列表外面的 `NotificationListener<ScrollNotification>`。
  ///
  /// 返回 `false` 表示**不拦**通知，列表该滚还怎么滚， 这里只顺手看一眼
  /// 要不要把日历折起来 / 展开。
  ///
  /// 折叠的呈现直接用 `TableCalendar` 自带的 `CalendarFormat.month ⇄ .week`：
  /// 它自己就是 `AnimatedSize` 包着的（`formatAnimationDuration` 默认 200ms），
  /// 高度变化是平滑的，不用我们再套一层动画；而且选中态、今天、小圆点标记
  /// 在周视图下全都照旧，比手画一条一周条稳得多。
  /// 折叠 / 展开的唯一入口。
  ///
  /// 不管是"上滑列表折起"、"点提示条"、"跟手拖完松手"，最后都走这里改状态；
  /// 视窗动画由 `FoldableCalendar` 监听这个状态统一收尾（动画只有一处，逻辑只有一处）。
  void setFolded(bool folded) {
    final next = folded ? CalendarFormat.week : CalendarFormat.month;
    if (calendarFormat.value != next) calendarFormat.value = next;
  }

  bool handleDayListScroll(ScrollNotification notification) {
    if (CalendarFoldSignal.isDragStart(notification)) {
      foldGesture.startDrag();
      return false;
    }

    final signal = CalendarFoldSignal.from(notification);
    if (signal == null) return false;

    final next = foldGesture.decide(
      current: calendarFormat.value,
      axis: notification.metrics.axis,
      pixels: notification.metrics.pixels,
      delta: signal.delta,
      isOverscroll: signal.isOverscroll,
      fromUser: signal.fromUser,
    );
    if (next != null) {
      setFolded(next == CalendarFormat.week);
    }
    return false;
  }

  Semester? getCurrentSemester() {
    final now = DateTime.now();
    return scholar.value.semesters.firstWhereOrNull((e) =>
        // 没套过校历的学期，firstDay/lastDay 是现在这个占位值，不能参与判断
        e.hasCalendar && !now.isBefore(e.firstDay) && !now.isAfter(e.lastDay));
  }

  /// 还没开始、但课表已经能看的学期。
  ///
  /// 开学前一天打开课表是很常见的场景（学期 9-14 开始，今天 9-13）：这时
  /// [getCurrentSemester] 是 null，课表却已经抓到了，不该给一张写着
  /// 当前不在学期内的白纸。
  ///
  /// ⚠️ 必须要求 [Semester.hasCalendar]：没有校历的学期 `firstDay` 返回的是
  /// 求值那一刻的现在，而 `now` 是先前捕获的， 那个值**必然晚于** `now`，
  /// 于是所有没配校历的学期都会被判成即将开学（实测会把 25-26 春夏选出来）。
  Semester? getUpcomingSemester() {
    final now = DateTime.now();
    final upcoming = scholar.value.semesters
        .where((e) => e.hasCalendar && e.firstDay.isAfter(now))
        .toList()
      ..sort((a, b) => a.firstDay.compareTo(b.firstDay));
    return upcoming.isEmpty ? null : upcoming.first;
  }

  /// 课表实际展示的学期：优先本学期，其次即将开学的那个。
  Semester? getDisplayedSemester() =>
      getCurrentSemester() ?? getUpcomingSemester();

  /// 该学期是否还没开学（页面上据此给一句提示）。
  bool isBeforeSemester(Semester semester) =>
      DateTime.now().isBefore(semester.firstDay);

  bool isFirstHalfSemester(Semester semester) {
    final now = DateTime.now();
    final toFirstWeek = now.difference(semester.firstDay).inDays ~/ 7;
    return toFirstWeek < 8;
  }

  String getCurrentSemesterDisplayName() {
    final semester = getDisplayedSemester();
    if (semester == null) return '无学期信息';

    final isFirstHalf = isFirstHalfSemester(semester);
    final semesterName =
        '${semester.name.substring(2, 5)}${semester.name.substring(7, 11)}';
    final halfName =
        isFirstHalf ? semester.firstHalfName : semester.secondHalfName;
    // 还没开学就说清楚，免得以为课表坏了
    final prefix = isBeforeSemester(semester) ? '未开学 · ' : '';
    return '$prefix$semesterName $halfName学期';
  }
}
