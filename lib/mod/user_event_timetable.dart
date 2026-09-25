import 'package:celechron/mod/user_event_date.dart';
import 'package:celechron/mod/user_event_periods.dart';

/// ============ 课表格子里的位置计算（纯逻辑）============
///
/// 课表那面是「13 行 × 周一到周日」的固定格子：
/// 一行 = 一节课，纵向坐标是 `(行号 - 1) / 13`。
/// 课程那边已经在 `schedule_view.dart` 里这么算了，本文件把同一套算法抽出来
/// 给**自定义日程**复用，免得两处各写一份、长得不一样。
///
/// ============ 为什么按时刻的日程要"取整到节" ============
///
/// 课表的行是离散的（第 1 节、第 2 节……），而例会通常是 19:00 这种钟点。
/// 用户的合理期待是"落在那节课的格子里"，所以反查包含它的那一节：
/// - 开始时刻落在哪一节里 → 从那一节开始；
/// - 结束时刻落在哪一节里 → 到那一节结束。
///
/// 一段 19:00-20:30 于是会占住第 11-12 两行，正好是它真正横跨的两节。
///
/// 它与 `user_event_periods.dart` 一样**不依赖 Flutter**（便于单测），
/// 界面只负责把算好的行区间画出来。
class TimetableRowLayout {
  const TimetableRowLayout._();

  /// 课表视图一共画几行。
  ///
  /// **2026-09-25 用户拍板：课表从 13 行扩到 15 行**（与真实校历一致）。
  /// 在此之前这里和 `schedule_view.dart` 都写死 13，而真实学期有 **15 节**
  /// （`assets/calendar/*.json` 的 `sessionTime`：第 1 节 08:00-08:45 …
  /// 第 15 节 22:10-22:55），导致第 14、15 节（21:20 之后）的**课程与自定义日程
  /// 都画不出来**。现在两边都用同一个数字，改的时候请一起改
  /// （`schedule_view.dart` 的 `_rowCount`）。
  static const int rowCount = 15;

  /// 一个时段在课表格子里占的行区间（**1 起、含两端**）。
  ///
  /// 返回 null 表示"这一格没法画"：换算表缺项、或者整段落在课表范围之外。
  /// **宁可不画，也不要画到错误的行上。**
  ///
  /// 实现上只有一条路径：把两个端点各自**反查**到所在的节。
  /// 按节次的日程不会走特殊分支 —— 它的端点正好等于某一节的首/尾，
  /// 反查的结果自然就是那两节。
  static ({int first, int last})? rowsOfSpan(
    EventSpan span,
    List<List<Duration>> periodTimes,
  ) {
    final first = _rowContaining(span.start, periodTimes);
    final last = _rowContaining(span.end, periodTimes, preferLast: true);
    if (first == null || last == null) return null;
    if (last < first) return null;
    return (first: first, last: last);
  }

  /// [time] 落在第几节里。
  ///
  /// 比较的是 **`Duration` 偏移量**（不是 `DateTime`）：换算表存的是"从当天
  /// 00:00 起的偏移"，所以用 `<=` / `>` 直接比大小，别去调
  /// `isAfter` / `isBefore`（那是 `DateTime` 的方法，`dart analyze` 会拦）。
  ///
  /// ===== 规则：取**距离最近的节边界**，平局取**靠前**那一节 =====
  ///
  /// 为什么不是"谁包含它就取谁"：真实的课间是 **5 分钟**（第 11 节 19:35 下课、
  /// 第 12 节 19:40 上课），所以"19:40 开始"这种钟点**不被任何一节包含**，
  /// 而"20:30 结束"正好落在第 12 节下车与第 13 节上课之间。
  /// 用距离算才说得清：20:30 离第 12 节的下课 5 分钟、离第 13 节的上课 0 分钟
  /// → 取第 13 节；而 12:25 离第 5 节下课 0 分钟、离第 6 节上课 60 分钟
  /// → 取第 5 节。
  ///
  /// ⚠️ 这一段的关键教训（写下来免得再犯）：上面那些 5 分钟/60 分钟的数字
  /// **必须来自真实校历**（`assets/calendar/*.json` 的 `sessionTime`，
  /// 第 1 节 08:00-08:45 … 第 12 节 19:40-**20:25** … 第 15 节 22:55 结束），
  /// 不能凭印象编一张表 —— 我编过一张"第 12 节到 20:30"的表，
  /// 于是推出了一条错的规则，靠单元测试才发现对不上。
  ///
  /// [preferLast] 现在只影响**平局**：距离一样时取靠前还是靠后。
  /// 给结束时刻用它取靠前（那节课刚下课），给开始时刻用它取靠后（下节课要上）。
  static int? _rowContaining(
    DateTime time,
    List<List<Duration>> periodTimes, {
    bool preferLast = false,
  }) {
    final offset = time.difference(userEventDateOnly(time));

    final firstRow = _firstRowOf(periodTimes);
    final lastRow = _lastRowOf(periodTimes);
    if (firstRow == null || lastRow == null) return null; // 换算表是空的

    int? best;
    Duration? bestDistance;
    for (var row = firstRow; row <= lastRow; row++) {
      final slot = periodTimes[row];
      if (slot.length < 2) continue;
      final distance = _distanceToSlot(slot, offset);
      if (bestDistance == null || distance < bestDistance) {
        best = row;
        bestDistance = distance;
        continue;
      }
      // 平局：靠前那节已经在 best 里，只有 preferLast=false 时才需要换成靠后那节
      if (distance == bestDistance && !preferLast) best = row;
    }
    return best;
  }

  /// [offset] 离这一节的**边界**有多远（落在节内就是 0）
  static Duration _distanceToSlot(List<Duration> slot, Duration offset) {
    if (offset < slot.first) return slot.first - offset;
    if (offset > slot.last) return offset - slot.last;
    return Duration.zero;
  }

  /// 换算表里第一条有效节次的行号；表是空的返回 null
  static int? _firstRowOf(List<List<Duration>> periodTimes) {
    for (var row = 1; row < periodTimes.length; row++) {
      if (periodTimes[row].length >= 2) return row;
    }
    return null;
  }

  /// 换算表里最后一条有效节次的行号；表是空的返回 null
  static int? _lastRowOf(List<List<Duration>> periodTimes) {
    for (var row = periodTimes.length - 1; row >= 1; row--) {
      if (periodTimes[row].length >= 2) return row;
    }
    return null;
  }

  /// 算一天的格子：把这一天要画的日程时段排好（第一行在前）。
  ///
  /// 关于重叠：**刻意不做自动重排**（SPEC.md D10 的结论是"叠加显示 + 角标"）。
  /// 这里不合并、不挪动，两件事撞在同一行就都返回，由界面画成叠着的样子。
  /// 这样用户一眼能看出"我这天的例会和课撞了"，而不是被悄悄挪到别的时间。
  static List<TimetableCell> layoutUserEvents({
    required int weekday,
    required Iterable<EventSpan> spans,
    required List<List<Duration>> periodTimes,
  }) {
    final cells = <TimetableCell>[];
    for (final span in spans) {
      final rows = rowsOfSpan(span, periodTimes);
      if (rows == null) continue;
      cells.add(TimetableCell(
        weekday: weekday,
        firstRow: rows.first,
        lastRow: rows.last,
        span: span,
      ));
    }
    cells.sort((a, b) {
      final byRow = a.firstRow.compareTo(b.firstRow);
      if (byRow != 0) return byRow;
      return a.lastRow.compareTo(b.lastRow);
    });
    return cells;
  }
}

/// 课表格子里的一个位置（给界面直接画）
class TimetableCell {
  /// 第几列：1 = 周一 … 7 = 周日
  final int weekday;

  /// 行区间（1 起、含两端）
  final int firstRow;
  final int lastRow;

  /// 画的是什么（自定义日程的时段；界面上要跟课程用颜色区别开）
  final EventSpan span;

  const TimetableCell({
    required this.weekday,
    required this.firstRow,
    required this.lastRow,
    required this.span,
  });

  /// 占了几个行高（界面用它算高度）
  int get rowSpan => lastRow - firstRow + 1;

  @override
  String toString() =>
      'TimetableCell(周$weekday 第$firstRow-$lastRow 节, ${span.title})';
}
