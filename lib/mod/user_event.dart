import 'package:celechron/mod/user_event_date.dart';
import 'package:celechron/mod/user_event_rule.dart';
import 'package:celechron/utils/json_utils.dart';

/// 自定义日程：**用户自己排的事**（学生组织例会、社团活动、固定家教……）。
///
/// ============ 它为什么不是一条 Task ============
///
/// 用户 2026-09-25 拍板（SPEC.md D1）：日程做成**新实体**。理由都写在
/// `SPEC.md` 的 3.1 与 D1 里，这里只留一句结论：日程没有「完成」这个语义，
/// 塞进 Task 就会被待办列表、完成逻辑、活动结束后自动归档一起带走。
///
/// ============ 与课程（Session）的关系 ============
///
/// 课表那套是教务给的**周次规则**（周几 + 第几节 + 单双周 + 上下半学期），
/// 具体日期由 `Semester._buildPeriods()` 展开。本模型**不碰教务**，
/// 也不进 `Semester`（那是教务数据的容器，每次刷新都会重建/合并），
/// 只在渲染时与课程合并（见 SPEC.md 3.1 末尾的说明）。
///
/// ============ 重复语义（SPEC.md D3，用户改过的口径）============
///
/// 用户定的口径是「**自然周几 + 截止日**」，**不是**学期周次：
/// 理由是放假期间也可能有这类活动，绑死学期周次会让假期里的例会用不了。
/// 所以时间只有一个概念：[startDate]（第一次发生的日期），
/// 之后每 [repeatPeriod] 周发生一次，直到 [repeatUntil] 为止。
///
/// 代价（如实记下，别以后当成 bug）：它**不跟校历的假期与调休走**（SPEC.md D6）。
/// 放假那天的例会不会自动消失，要用户自己删那几条或改截止日。
class UserEvent {
  /// 主键，uuid v4
  final String uid;

  /// 标题，如「学生会例会」
  final String title;

  /// **第一次发生的日期**（只取日期部分，时间部分会被丢弃）。
  ///
  /// 它同时承担两个语义，所以没有再单开一个「基准日」字段：
  /// 1. 从这天开始（早于它的日期一律不发生）；
  /// 2. 「每两周 / 每 N 周」的**奇偶基准**（见 `user_event_rule.dart`）。
  final DateTime startDate;

  /// 1 = 周一 … 7 = 周日，与 `DateTime.weekday` 和 `Session.dayOfWeek` 同一套。
  ///
  /// **必须与 [startDate] 的星期几一致**。构造时会自动纠正（见 [UserEvent] 构造函数），
  /// 因为不一致的后果是「这条日程永远不发生」这种静默故障，用户根本查不出来。
  ///
  /// ⚠️ **它是派生字段，`toMap` 故意不写它**（导出文件里看不到 `dayOfWeek` 是正常的）：
  /// 唯一真源是 [startDate]，存两份迟早不一致。`fromMap` 仍然认这个键 ——
  /// 那是为了能读别人（或旧版本）写进来的数据，缺了就从 [startDate] 现算。
  /// 别为了"导出里少个字段"去把它补进 `toMap`。
  final int dayOfWeek;

  /// 第几节到第几节（1..13），与 `Session.time` 同一套编号。
  /// 与 [startClock] / [endClock] **二选一**。
  final int? startPeriod;
  final int? endPeriod;

  /// 具体时刻，形如 `"19:00"` / `"20:30"`。与节次**二选一**。
  ///
  /// 为什么两种都留（SPEC.md D4）：例会通常按钟点开（19:00），
  /// 而课表是按节次排版的，只有两种都支持才能在课表格子里对齐。
  final String? startClock;
  final String? endClock;

  /// 重复间隔，单位是**周**：1 = 每周、2 = 每两周、3 = 每三周……
  ///
  /// - 命名与 `Task.repeatPeriod` 对齐（那边单位是天）；
  /// - **0 表示「只这一次」**（用户 2026-09-25 定：不再单开一个 `onlyOnce` 布尔字段，
  ///   因为「间隔为 0 周」本身就是不会重复的意思，一个字段说一件事）。
  final int repeatPeriod;

  /// 重复到哪一天为止（含这一天）。`null` = **一直重复，没有终点**。
  ///
  /// SPEC.md D11：新建时默认预填「本学期最后一天」，**且允许清空**。
  /// 清空就是「放假也要用」的出口。**发生判定本身不看学期**，
  /// 学期只决定这个默认值填什么、以及画在课表哪张表上。
  final DateTime? repeatUntil;

  /// 归属学期（`Semester.name`，如 `2026-2027-1春夏`）。**只用于展示归属**，
  /// 不参与发生判定。`null` = 不限。
  final String? semesterName;

  /// 地点
  final String location;

  /// 备注
  final String note;

  /// 用户自选的颜色（ARGB）。`null` = 用固定粉
  /// `UserEventColors.defaultEventColor`（SPEC.md R3）。
  final int? color;

  /// 是否提醒。**字段先留着，第一期不做投递**（SPEC.md D5）：
  /// 先留字段是为了以后加功能时不用动同步协议。
  final bool reminderEnabled;

  /// 提前多少分钟提醒。`null` = 沿用设置里的默认值。
  final int? reminderLeadMinutes;

  final DateTime createdAt;
  final DateTime updatedAt;

  UserEvent({
    required this.uid,
    required this.title,
    // 这三个字段要**加工后**再存（只取日期部分 / 按开始日期纠正周几），
    // 所以不能写成 `this.startDate` 这种形参直接赋值：
    // 同一个字段既在参数表又在初始化列表里赋值，Dart 会直接报
    // field_initialized_in_parameter_and_initializer（dart analyze 实测会红）。
    DateTime? startDate,
    DateTime? repeatUntil,
    required int dayOfWeek,
    this.startPeriod,
    this.endPeriod,
    this.startClock,
    this.endClock,
    this.repeatPeriod = 1,
    this.semesterName,
    this.location = '',
    this.note = '',
    this.color,
    this.reminderEnabled = false,
    this.reminderLeadMinutes,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : startDate = userEventDateOnly(startDate!),
        repeatUntil = repeatUntil == null ? null : userEventDateOnly(repeatUntil),
        // ===== 自洽校验（SPEC.md 3.3 的易错点第 2 条）=====
        //
        // 周几与开始日期不一致时**以开始日期为准**自动纠正，传进来的值被忽略。
        // 不能只报错不纠正：编辑页里用户先改日期、后改周几是常态，
        // 中途那个不自洽的状态是合法的中间态，报错会让人没法改。
        dayOfWeek = userEventDateOnly(startDate).weekday,
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  /// 只发生一次（不重复）
  bool get isSingleOccurrence => repeatPeriod <= 0;

  /// 按节次排的（否则就是按具体时刻排的）
  bool get usesPeriod => startPeriod != null;

  /// 生效的最后一天：只这一次就是开始那天；有截止日就是那天；否则 `null` = 无终点。
  DateTime? get lastDay => isSingleOccurrence ? startDate : repeatUntil;

  /// 是否在 [day] 这一天发生（判定逻辑全在 `user_event_rule.dart`，见那里的解释）
  bool occursOn(DateTime day) => UserEventRule.occursOn(this, day);

  /// 取一份改动后的副本。
  ///
  /// 与 `Task.copyWith` 同一套写法：**可变字段用 `copyWith` 传值覆盖**。
  /// 注意改 [startDate] 时周几会跟着自动纠正（见构造函数），这是刻意的。
  UserEvent copyWith({
    String? uid,
    String? title,
    DateTime? startDate,
    int? dayOfWeek,
    int? startPeriod,
    int? endPeriod,
    String? startClock,
    String? endClock,
    int? repeatPeriod,
    DateTime? repeatUntil,
    bool clearRepeatUntil = false,
    String? semesterName,
    String? location,
    String? note,
    int? color,
    bool? reminderEnabled,
    int? reminderLeadMinutes,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return UserEvent(
      uid: uid ?? this.uid,
      title: title ?? this.title,
      startDate: startDate ?? this.startDate,
      // 没显式给 dayOfWeek 时传 null 让它按 startDate 自动算；
      // 但 UserEvent 的构造函数拿不到"原来的值"，所以这里显式传：
      dayOfWeek: startDate != null
          ? userEventDateOnly(startDate).weekday
          : (dayOfWeek ?? this.dayOfWeek),
      startPeriod: startPeriod ?? this.startPeriod,
      endPeriod: endPeriod ?? this.endPeriod,
      startClock: startClock ?? this.startClock,
      endClock: endClock ?? this.endClock,
      repeatPeriod: repeatPeriod ?? this.repeatPeriod,
      // 显式清空截止日要一个开关：否则传 null 与"不传"无法区分
      repeatUntil: clearRepeatUntil ? null : (repeatUntil ?? this.repeatUntil),
      semesterName: semesterName ?? this.semesterName,
      location: location ?? this.location,
      note: note ?? this.note,
      color: color ?? this.color,
      reminderEnabled: reminderEnabled ?? this.reminderEnabled,
      reminderLeadMinutes: reminderLeadMinutes ?? this.reminderLeadMinutes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  // ------------------------------------------------------------ 存与取
  //
  // 走**一份 Map/JSON**，与 `CourseMount` 同一招：不新增 Hive typeId、
  // 不注册 adapter（理由见 `lib/model/course_mount.dart` 顶部那段）。
  // 键用**稳定字符串**而不是字段序号：序号在版本间会漂移，跨设备会读错字段
  // （这是 `lib/utils/task_json.dart` 已经定下的口径）。

  Map<String, dynamic> toMap() => <String, dynamic>{
        'uid': uid,
        'title': title,
        'startDate': startDate.millisecondsSinceEpoch,
        'repeatPeriod': repeatPeriod,
        'repeatUntil': repeatUntil?.millisecondsSinceEpoch,
        'semesterName': semesterName,
        'location': location,
        'note': note,
        'color': color,
        'reminderEnabled': reminderEnabled,
        'reminderLeadMinutes': reminderLeadMinutes,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'updatedAt': updatedAt.millisecondsSinceEpoch,
        if (startPeriod != null) 'startPeriod': startPeriod,
        if (endPeriod != null) 'endPeriod': endPeriod,
        if (startClock != null) 'startClock': startClock,
        if (endClock != null) 'endClock': endClock,
      };

  /// 从存下来的 Map 还原。**读不动就返回 `null`**，由调用方（store）
  /// 决定丢掉这一条还是整批放弃；绝不在这里抛异常，这是用户数据。
  static UserEvent? fromMap(Map<dynamic, dynamic>? raw) {
    if (raw == null) return null;
    final uid = asString(raw['uid']);
    final title = asString(raw['title']);
    final startMillis = asInt(raw['startDate']);
    if (uid == null || uid.isEmpty || startMillis == null) return null;

    final startDate =
        DateTime.fromMillisecondsSinceEpoch(startMillis);
    final repeatUntilMillis = asInt(raw['repeatUntil']);

    // 节次与时刻二选一：两边都缺就没法排版，整条丢掉
    final startPeriod = asInt(raw['startPeriod']);
    final startClock = asString(raw['startClock']);
    if (startPeriod == null && startClock == null) return null;

    return UserEvent(
      uid: uid,
      title: title ?? '',
      startDate: startDate,
      // 存的是旧值时也不怕：构造函数会按 startDate 纠正
      dayOfWeek: asInt(raw['dayOfWeek']) ?? startDate.weekday,
      startPeriod: startPeriod,
      endPeriod: asInt(raw['endPeriod']),
      startClock: startClock,
      endClock: asString(raw['endClock']),
      repeatPeriod: asInt(raw['repeatPeriod']) ?? 1,
      repeatUntil: repeatUntilMillis == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(repeatUntilMillis),
      semesterName: asString(raw['semesterName']),
      location: asString(raw['location']) ?? '',
      note: asString(raw['note']) ?? '',
      color: asInt(raw['color']),
      reminderEnabled: asBool(raw['reminderEnabled']) ?? false,
      reminderLeadMinutes: asInt(raw['reminderLeadMinutes']),
      createdAt: asInt(raw['createdAt']) == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(asInt(raw['createdAt'])!),
      updatedAt: asInt(raw['updatedAt']) == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(asInt(raw['updatedAt'])!),
    );
  }

  /// 「19:00」或「第 5-6 节」这种给人看的时间段
  String get timeLabel {
    if (usesPeriod) {
      final last = endPeriod ?? startPeriod!;
      return last == startPeriod ? '第 $startPeriod 节' : '第 $startPeriod-$last 节';
    }
    final from = startClock ?? '';
    final to = endClock;
    if (to == null || to == from) return from;
    return '$from-$to';
  }

  /// 「每周一」「每两周的周三」这种给人看的重复说法
  String get repeatLabel {
    const names = ['一', '二', '三', '四', '五', '六', '日'];
    final week = dayOfWeek >= 1 && dayOfWeek <= 7 ? names[dayOfWeek - 1] : '?';
    if (isSingleOccurrence) {
      return '仅 ${startDate.month} 月 ${startDate.day} 日（周$week）';
    }
    if (repeatPeriod == 1) return '每周$week';
    return '每 $repeatPeriod 周的周$week';
  }

  @override
  String toString() => 'UserEvent($title, $repeatLabel $timeLabel)';
}
