import 'package:celechron/mod/user_event.dart';
import 'package:celechron/mod/user_event_clock.dart';
import 'package:celechron/mod/user_event_date.dart';

/// 日程按什么填时间
enum UserEventTimeMode {
  /// 第几节到第几节（与课表同一套编号，好在课表格子里对齐）
  period,

  /// 具体时刻（19:00-20:30 这种，例会最常见的填法）
  clock,
}

/// ============ 编辑页的草稿与校验（纯逻辑，不碰界面）============
///
/// 编辑页只负责把用户输入塞进这个草稿、把 [validate] 的结果显示出来、
/// 然后调 [build] 拿到可以落库的 [UserEvent]。
/// 校验单独放这里（而不是写在 Widget 里）的理由很实际：
/// **校验漏了不会报错，只会存进去一条"永远不发生的日程"**，
/// 用户完全看不出哪里错了。所以它必须能被单测逐条钉住。
///
/// 它与 `user_event_date.dart` / `user_event_clock.dart` 一样**不依赖 Flutter**。
class UserEventDraft {
  /// 节次编号的上限。校历实际是 13 节，多留几节给海宁那种特殊作息
  /// （BACKLOG 旧清单第 23 项记过"课表时间段问题"）。
  static const int maxPeriod = 16;

  static const int minRepeatPeriod = 0; // 0 = 只这一次
  static const int maxRepeatPeriod = 8; // 每 8 周一次，够用了

  /// 编辑已存在的日程时带上它；新建时为 null
  final String? uid;

  String title;

  /// 第一次发生的日期
  DateTime startDate;

  UserEventTimeMode timeMode;

  /// 按节次：第几节到第几节
  int startPeriod;
  int endPeriod;

  /// 按时刻：`"19:00"` / `"20:30"`
  String startClock;
  String endClock;

  /// 0 = 只这一次；1 = 每周；2 = 每两周……
  int repeatPeriod;

  /// 重复到哪一天（null = 一直重复）
  DateTime? repeatUntil;

  /// 归属学期（只用于展示归属，不参与发生判定）
  String? semesterName;

  String location;
  String note;
  int? color;
  bool reminderEnabled;
  int? reminderLeadMinutes;

  UserEventDraft({
    this.uid,
    this.title = '',
    required this.startDate,
    this.timeMode = UserEventTimeMode.clock,
    this.startPeriod = 1,
    this.endPeriod = 1,
    this.startClock = '19:00',
    this.endClock = '20:30',
    this.repeatPeriod = 1,
    this.repeatUntil,
    this.semesterName,
    this.location = '',
    this.note = '',
    this.color,
    this.reminderEnabled = false,
    this.reminderLeadMinutes,
  });

  /// 从已存在的日程生成草稿（编辑入口用）
  factory UserEventDraft.of(UserEvent event) => UserEventDraft(
        uid: event.uid,
        title: event.title,
        startDate: event.startDate,
        timeMode:
            event.usesPeriod ? UserEventTimeMode.period : UserEventTimeMode.clock,
        startPeriod: event.startPeriod ?? 1,
        endPeriod: event.endPeriod ?? event.startPeriod ?? 1,
        startClock: event.startClock ?? '19:00',
        endClock: event.endClock ?? event.startClock ?? '20:30',
        repeatPeriod: event.repeatPeriod,
        repeatUntil: event.repeatUntil,
        semesterName: event.semesterName,
        location: event.location,
        note: event.note,
        color: event.color,
        reminderEnabled: event.reminderEnabled,
        reminderLeadMinutes: event.reminderLeadMinutes,
      );

  /// 保存前的校验。返回**人话**的错误清单；空表 = 可以保存。
  ///
  /// 逐条说明为什么值得拦：
  /// - 标题为空：列表上会显示成空白一条，用户根本认不出那是自己建的；
  /// - 节次越界 / 开始晚于结束：时间换算会拿不到值或折成一个点，
  ///   表现为"日程存了但日历上看不见"；
  /// - 时刻写坏：同上（`parseClock` 认不出来就返回 null，那条就不画）；
  /// - 每 N 周的 N 越界：0 与负数是"只这一次"的意思，但输入框里出现负数
  ///   一定是误操作。
  List<String> validate() {
    final errors = <String>[];

    if (title.trim().isEmpty) {
      errors.add('请填标题');
    }

    if (timeMode == UserEventTimeMode.period) {
      if (startPeriod < 1 || startPeriod > maxPeriod) {
        errors.add('开始节次要在 1 到 $maxPeriod 之间');
      }
      if (endPeriod < 1 || endPeriod > maxPeriod) {
        errors.add('结束节次要在 1 到 $maxPeriod 之间');
      }
      if (endPeriod < startPeriod) {
        errors.add('结束节次不能早于开始节次');
      }
    } else {
      if (userEventParseClock(startClock) == null) {
        errors.add('开始时刻填得不对（要像 19:00 这样）');
      }
      if (userEventParseClock(endClock) == null) {
        errors.add('结束时刻填得不对（要像 20:30 这样）');
      }
    }

    if (repeatPeriod < minRepeatPeriod || repeatPeriod > maxRepeatPeriod) {
      errors.add('重复间隔要在 $minRepeatPeriod 到 $maxRepeatPeriod 周之间');
    }

    final until = repeatUntil;
    if (until != null && userEventDateOnly(until).isBefore(userEventDateOnly(startDate))) {
      errors.add('重复截止日不能早于开始日期');
    }

    return errors;
  }

  /// 能不能保存
  bool get isValid => validate().isEmpty;

  /// 造一条可以落库的日程。
  ///
  /// **校验不过返回 `null`**（而不是造一条半成品）：调用方要先看 [validate]，
  /// 这里的 null 只是最后一道防线。
  ///
  /// 周几**不在这里填对**：`UserEvent` 的构造函数一律按 `startDate` 纠正好，
  /// 所以调用方给什么都不影响（这也是"永远不发生"那个坑的解药）。
  UserEvent? build({DateTime? now}) {
    if (!isValid) return null;
    final stamp = now ?? DateTime.now();
    final isPeriod = timeMode == UserEventTimeMode.period;
    return UserEvent(
      uid: uid ?? _newUid(stamp),
      title: title.trim(),
      startDate: userEventDateOnly(startDate),
      dayOfWeek: userEventDateOnly(startDate).weekday,
      startPeriod: isPeriod ? startPeriod : null,
      endPeriod: isPeriod ? endPeriod : null,
      startClock: isPeriod ? null : startClock.trim(),
      endClock: isPeriod ? null : endClock.trim(),
      repeatPeriod: repeatPeriod,
      repeatUntil: repeatUntil,
      semesterName: semesterName,
      location: location.trim(),
      note: note.trim(),
      color: color,
      reminderEnabled: reminderEnabled,
      reminderLeadMinutes: reminderLeadMinutes,
      createdAt: stamp,
      updatedAt: stamp,
    );
  }

  /// 新建时用的 uid。
  ///
  /// 用"时间戳 + 一段随机"而不是引 `uuid` 包：`uuid` 已经在依赖里
  /// （`Period.genUid` 在用），但这里刻意少一个依赖面，
  /// 而且 uid 只要在同一台设备上唯一即可（跨设备合并靠的是它不重复）。
  static int _uidSeq = 0;

  static String _newUid(DateTime stamp) {
    _uidSeq++;
    final base = stamp.microsecondsSinceEpoch.toRadixString(36);
    final seq = _uidSeq.toRadixString(36);
    final salt = stamp.hashCode.toRadixString(36).replaceAll('-', '');
    return 'evt-$base-$seq-$salt';
  }

  /// 改开始日期时顺手把时间口径带过去（编辑页的日期选择器回调里用）
  void setStartDate(DateTime date) {
    startDate = userEventDateOnly(date);
  }

  /// 给人看的时间描述（列表与卡片上用）
  String get timeLabel {
    if (timeMode == UserEventTimeMode.period) {
      return endPeriod == startPeriod
          ? '第 $startPeriod 节'
          : '第 $startPeriod-$endPeriod 节';
    }
    return '$startClock-$endClock';
  }

  /// 给人看的重复描述
  String get repeatLabel {
    if (repeatPeriod == 0) return '只这一次';
    if (repeatPeriod == 1) return '每周';
    return '每 $repeatPeriod 周';
  }
}
