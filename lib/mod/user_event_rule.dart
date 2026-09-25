import 'package:celechron/mod/user_event.dart';
import 'package:celechron/mod/user_event_date.dart';

/// ============ 自定义日程的「发生判定」 ============
///
/// 这个类**只回答一个问题**：某个日期，这条日程发生吗？
///
/// 它是**纯函数**：不碰界面、不碰数据库、不看当前时间、不依赖学期或校历
/// （与 `class_reminder_rule.dart` 同一套路），所以能直接单测。
///
/// ============ 口径（SPEC.md D3，用户 2026-09-25 改过）============
///
/// 「**自然周几 + 截止日**」，不是学期周次。用户的原话理由：
/// **放假也可能有这类活动**。绑死学期周次的话，假期里的例会用不了。
///
/// 于是判定只有四步，见 [occursOn]。
///
/// ============ 与校历的关系：**没有关系**（SPEC.md D6）============
///
/// 校历里的假期（`Semester._holidays`）与调休（`Semester._exchanges`）
/// 会作用在**课程**上：课程在那两步被砍掉或搬到另一天
/// （见 `semester.dart` 的 `_buildPeriods()`）。
/// **自定义日程一律不参与**，原因有两个，都不是"忘了做"：
///
/// 1. 调休的本质是"把某一天的课搬到另一天"，而自然周几的日程
///    **没有课程表这个概念**，也就没有可搬的目标日；
/// 2. 用户要的就是"放假也能用"，放假那天自动消失反而与需求相反。
///
/// 代价说清楚：中秋、国庆放假那天的例会不会自动消失，
/// **要用户自己删那几条或改截止日**（"只删这一次"是另一个待办项，
/// 见 `docs/BACKLOG.md` 的 L2）。
class UserEventRule {
  const UserEventRule._();

  /// [day] 这一天，[event] 发生吗？
  ///
  /// 四步，任何一步不满足就 false：
  /// 1. 星期几对得上吗
  /// 2. 不早于第一次发生的日期吗
  /// 3. 重复口径满足吗（见下面的三分支）
  /// 4. 不晚于截止日吗（没有截止日则永远满足）
  static bool occursOn(UserEvent event, DateTime day) {
    final target = userEventDateOnly(day);
    final first = userEventDateOnly(event.startDate);

    // 1. 星期几
    if (target.weekday != event.dayOfWeek) return false;

    // 2. 起点之前一律不发生
    if (target.isBefore(first)) return false;

    // 3. 重复口径：分三种情况，别写成"两个 if 套着"，那样漏一种查不出来
    //
    // ⚠️ 这里踩过一次（靠临时验证程序抓到的，不是靠读代码看出来的）：
    // 原来写成 `if (!isSingleOccurrence) { 检查整周差 }`，
    // 于是 repeatPeriod = 0 时**整段检查被跳过**，第 4 步又没有截止日拦着，
    // 结果「只这一次」被当成了「每周」—— 9/14 建的日程，9/21 也发生。
    // 现在两种口径各写各的，单测第 3、4 段把这个回归钉死。
    if (event.isSingleOccurrence) {
      // 只这一次：只有第一次那一天
      if (target != first) return false;
    } else {
      // 周期重复：相隔的**整周数**必须能被间隔整除
      final weeks = target.difference(first).inDays ~/ 7;
      if (weeks % event.repeatPeriod != 0) return false;
    }

    // 4. 截止日（含端点）
    final until = event.repeatUntil;
    if (until != null && target.isAfter(userEventDateOnly(until))) return false;

    return true;
  }

  /// [from] 到 [to] 之间（**两端都含**）这条日程的所有发生日期，按时间升序。
  ///
  /// 给"扫一段日期看有没有日程"的调用方用（课表那面就是按周扫）。
  /// [maxDays] 是护栏：传进来的区间畸形（比如 200 年）时不至于把内存吃光。
  static List<DateTime> occurrencesBetween(
    UserEvent event,
    DateTime from,
    DateTime to, {
    int maxDays = 400,
  }) {
    final start = userEventDateOnly(from);
    final end = userEventDateOnly(to);
    if (end.isBefore(start)) return const <DateTime>[];

    final result = <DateTime>[];
    var day = start;
    var guard = 0;
    while (!day.isAfter(end) && guard < maxDays) {
      if (occursOn(event, day)) result.add(day);
      day = DateTime(day.year, day.month, day.day + 1);
      guard++;
    }
    return result;
  }

  /// [from] 之后（含 [from] 当天）第一次发生的日期；[lookaheadDays] 内找不到就 null。
  ///
  /// 给"接下来"列表与以后做提醒用。**没有终点**的日程也要能算出下一次，
  /// 所以这里必须有个搜索上限：正常间隔是 1 或 2 周，[lookaheadDays] 默认给一年绰绰有余。
  static DateTime? nextOccurrence(
    UserEvent event,
    DateTime from, {
    int lookaheadDays = 366,
  }) {
    final start = userEventDateOnly(from);
    final last = event.lastDay;
    // 已经过了最后一天，不用找了
    if (last != null && start.isAfter(userEventDateOnly(last))) return null;

    var day = start;
    for (var i = 0; i <= lookaheadDays; i++) {
      if (occursOn(event, day)) return day;
      day = DateTime(day.year, day.month, day.day + 1);
    }
    return null;
  }
}
