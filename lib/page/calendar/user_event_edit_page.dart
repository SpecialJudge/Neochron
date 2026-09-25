import 'package:celechron/design/app_accent.dart';
import 'package:celechron/design/date_picker_sheet.dart';
import 'package:celechron/design/page_background.dart';
import 'package:celechron/design/repeat_sheet.dart';
import 'package:celechron/design/user_event_palette.dart';
import 'package:celechron/mod/user_event.dart';
import 'package:celechron/mod/user_event_clock.dart';
import 'package:celechron/mod/user_event_draft.dart';
import 'package:celechron/model/task.dart' show TaskRepeatType;
import 'package:flutter/cupertino.dart';

/// 编辑页退出时告诉调用方"发生了什么"。
///
/// 为什么不直接 `pop(UserEvent?)`：还要能表达**删除**这一种结果。
/// 用哨兵值（比如返回 null 当删除）会取消与删除分不清，
/// 所以给一个小结构体，`switch` 一眼看明白。
enum UserEventEditAction { saved, deleted }

class UserEventEditResult {
  final UserEventEditAction action;

  /// 保存时是那条日程；删除时为 null
  final UserEvent? event;

  const UserEventEditResult.saved(this.event)
      : action = UserEventEditAction.saved;

  const UserEventEditResult.deleted()
      : action = UserEventEditAction.deleted,
        event = null;
}

/// 新建 / 编辑自定义日程的页面（SPEC.md 步 4）。
///
/// 交互与配色照 `task_create_page.dart`（钉钉风）：标题大字号直接写在顶上，
/// 其余是一行行的设置项；右上角保存、左上角关闭。
///
/// **返回契约**：保存成功时 `pop(UserEventEditResult.saved(event))`；
/// 删除时（只有 [allowDelete] 为 true 才有那个按钮）`pop(…deleted())`；
/// 取消时 `pop(null)`。
/// 落库由调用方负责（它拿得到 `DatabaseHelper`），这个页面只管收集输入与校验。
///
/// 校验全部交给 [UserEventDraft.validate]（纯逻辑、有单测），
/// 这里只负责把错误用弹窗说人话地显示出来 —— 不在这里重复写一套规则，
/// 否则规则一改两处就会不一致。
class UserEventEditPage extends StatefulWidget {
  /// 要编辑的草稿；新建时传一个默认值（见 [UserEventDraft.newDraft]）
  final UserEventDraft initial;

  /// 新建时是「新建日程」，编辑时是「编辑日程」
  final String pageTitle;

  /// 编辑既有日程时给 true：左上角会多一个删除入口
  final bool allowDelete;

  const UserEventEditPage({
    super.key,
    required this.initial,
    this.pageTitle = '新建日程',
    this.allowDelete = false,
  });

  @override
  State<UserEventEditPage> createState() => _UserEventEditPageState();
}

class _UserEventEditPageState extends State<UserEventEditPage> {
  late UserEventDraft _draft;
  final _titleController = TextEditingController();
  final _locationController = TextEditingController();
  final _noteController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _draft = widget.initial;
    // 把草稿里的文字回填到输入框（编辑既有日程时会预填）
    _titleController.text = _draft.title;
    _locationController.text = _draft.location;
    _noteController.text = _draft.note;
    // 标题变化时刷新右上角"保存"的可用状态
    _titleController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _titleController.dispose();
    _locationController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- 保存

  bool get _canSave => _titleController.text.trim().isNotEmpty;

  void _save() {
    _draft.title = _titleController.text;
    _draft.location = _locationController.text;
    _draft.note = _noteController.text;

    final errors = _draft.validate();
    if (errors.isNotEmpty) {
      _alert(errors.first, detail: errors.length > 1 ? errors.sublist(1) : null);
      return;
    }
    final event = _draft.build();
    if (event == null) {
      // 理论上到不了这里（上面已经校验过），兜一句免得静默失败
      _alert('这条日程还存不了', detail: const ['请检查标题与时间']);
      return;
    }
    Navigator.of(context).pop(UserEventEditResult.saved(event));
  }

  /// 删除整条日程（SPEC.md D7：第一期只做整条删，不做"只删这一次"）
  Future<void> _delete() async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (BuildContext context) => CupertinoAlertDialog(
        title: const Text('删除这条日程？'),
        content: Text(
          '「${_draft.title.trim().isEmpty ? "未命名" : _draft.title.trim()}」'
          '会从日历、课表与「接下来」里一起消失。',
        ),
        actions: [
          CupertinoDialogAction(
            child: const Text('取消'),
            onPressed: () => Navigator.of(context).pop(false),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            child: const Text('删除'),
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    Navigator.of(context).pop(const UserEventEditResult.deleted());
  }

  void _alert(String message, {List<String>? detail}) {
    showCupertinoDialog<void>(
      context: context,
      builder: (BuildContext context) => CupertinoAlertDialog(
        title: Text(message),
        content: detail == null || detail.isEmpty
            ? null
            : Text(detail.map((item) => '· $item').join('\n')),
        actions: [
          CupertinoDialogAction(
            child: const Text('知道了'),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- 选择器

  /// 开始日期：用日历弹窗（带课程/日程小圆点，与主日历一致）
  Future<void> _pickStartDate() async {
    final picked = await showDateTimeSheet(
      context,
      initial: _draft.startDate,
      title: '第一次发生的日期',
      // 只填日期不填时刻：时刻由"按节次/按时刻"那两行决定
      withTime: false,
    );
    if (picked == null || !mounted) return;
    setState(() => _draft.setStartDate(picked));
  }

  /// 具体时刻：交给系统时间滚轮（`showDateTimeSheet` 的一行）
  Future<void> _pickClock({required bool isStart}) async {
    final current =
        userEventParseClock(isStart ? _draft.startClock : _draft.endClock) ??
            (isStart ? (19, 0) : (20, 30));
    final picked = await showDateTimeSheet(
      context,
      initial: DateTime(2026, 1, 1, current.$1, current.$2),
      title: isStart ? '开始时刻' : '结束时刻',
    );
    if (picked == null || !mounted) return;
    setState(() {
      final text = userEventFormatClock(picked.hour, picked.minute);
      if (isStart) {
        _draft.startClock = text;
        // 结束比开始早（且不是刻意的跨零点）时跟着往后挪半小时，省得每次都要改两下
        final end = userEventParseClock(_draft.endClock);
        if (end != null && end.$1 * 60 + end.$2 <= picked.hour * 60 + picked.minute) {
          final plus = picked.add(const Duration(minutes: 30));
          _draft.endClock = userEventFormatClock(plus.hour, plus.minute);
        }
      } else {
        _draft.endClock = text;
      }
    });
  }

  /// 重复规则：复用待办那套"每 N 周"的弹窗，不另造一个
  Future<void> _pickRepeat() async {
    final initial = _draft.repeatPeriod == 0
        ? RepeatSetting.fromUnit(
            unit: RepeatUnit.week, interval: 1, endless: true)
        : RepeatSetting.fromUnit(
            unit: RepeatUnit.week,
            interval: _draft.repeatPeriod,
            endless: _draft.repeatUntil == null,
            endsDate: _draft.repeatUntil,
          );
    final picked = await showRepeatSheet(context, initial);
    if (picked == null || !mounted) return;
    setState(() {
      if (picked.type == TaskRepeatType.norepeat) {
        _draft.repeatPeriod = 0;
        return;
      }
      // 只认"每 N 周"：这个功能的语义就是按周
      final weeks = picked.unit == RepeatUnit.week ? picked.interval : 1;
      _draft.repeatPeriod = weeks.clamp(
        UserEventDraft.minRepeatPeriod == 0 ? 1 : UserEventDraft.minRepeatPeriod,
        UserEventDraft.maxRepeatPeriod,
      );
      _draft.repeatUntil = picked.endless ? null : picked.endsDate;
    });
  }

  Future<void> _pickUntil() async {
    final picked = await showDateTimeSheet(
      context,
      initial: _draft.repeatUntil ?? _draft.startDate,
      title: '重复到哪一天',
      withTime: false,
    );
    if (picked == null || !mounted) return;
    setState(() => _draft.repeatUntil = picked);
  }

  // ---------------------------------------------------------------- 界面

  /// 一行设置项：左边名字，右边当前值（+ 可选的小箭头）
  ///
  /// ===== 布局：名字 + Expanded(值) + 可选小箭头 =====
  ///
  /// 这里踩过一个坑（2026-09-25 真机发现，两个症状同一个原因）：
  /// 原来写的是 `Text(label)` + `Spacer()` + `Flexible(Text(value))`。
  /// **`Spacer` 会把剩余空间全吃掉**，于是后面那个 `Flexible` 只能缩到
  /// 内容的固有宽度、紧贴 Spacer 的右边缘停住 —— 造成的现象是：
  ///
  /// 1. 「每周」看着**没有右对齐**（它右对齐在"自己那个窄盒子"里，
  ///    而不是在整个剩余空间的右边）；
  /// 2. 「第一次发生在」「重复到」这种长文本被压窄 → **明明还有空间却出现省略号**。
  ///
  /// 改成一个 `Expanded` 包住值文本：`Expanded` 拿满剩余宽度，
  /// `textAlign: TextAlign.right` 才真的是"靠到行的右边"，
  /// 同时长文本也就有了完整的宽度可用。
  Widget _row({
    required BuildContext context,
    required IconData icon,
    required String label,
    required String value,
    VoidCallback? onTap,
    Color? valueColor,
    Widget? trailing,
  }) {
    final accent = AppAccent.primary;
    final labelColor =
        CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context);
    return CupertinoButton(
      padding: EdgeInsets.zero,
      pressedOpacity: onTap == null ? 1 : 0.6,
      onPressed: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            Icon(icon, size: 19, color: accent),
            const SizedBox(width: 12),
            Text(label, style: TextStyle(fontSize: 16, color: labelColor)),
            if (trailing == null)
              Expanded(
                child: Text(
                  value,
                  textAlign: TextAlign.right,
                  // 两行封顶：再长也留得住，不会把这一行撑高到看不出是"一行设置项"
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: valueColor ??
                        CupertinoTheme.of(context).textTheme.textStyle.color,
                  ),
                ),
              )
            else ...[
              const SizedBox(width: 8),
              Expanded(child: Align(alignment: Alignment.centerRight, child: trailing)),
            ],
            if (onTap != null) ...[
              const SizedBox(width: 4),
              const Icon(CupertinoIcons.chevron_forward,
                  size: 15, color: CupertinoColors.tertiaryLabel),
            ],
          ],
        ),
      ),
    );
  }

  Widget _divider(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 47),
        child: Container(
          height: 0.5,
          color: CupertinoDynamicColor.resolve(
              CupertinoColors.separator, context),
        ),
      );

  Widget _card({required BuildContext context, required List<Widget> children}) =>
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        child: Container(
          decoration: BoxDecoration(
            color: CupertinoDynamicColor.resolve(
                CupertinoColors.secondarySystemGroupedBackground, context),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(children: children),
        ),
      );

  /// 时间口径那两行（按节次 / 按时刻）
  Widget _timeCard(BuildContext context) {
    final isPeriod = _draft.timeMode == UserEventTimeMode.period;
    return _card(
      context: context,
      children: [
        // 口径切换
        _row(
          context: context,
          icon: CupertinoIcons.time,
          label: '怎么填时间',
          value: '',
          trailing: CupertinoSlidingSegmentedControl<UserEventTimeMode>(
            groupValue: _draft.timeMode,
            thumbColor: AppAccent.soft(0.25),
            children: const {
              UserEventTimeMode.period: Padding(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                child: Text('按节次', style: TextStyle(fontSize: 14)),
              ),
              UserEventTimeMode.clock: Padding(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                child: Text('按时刻', style: TextStyle(fontSize: 14)),
              ),
            },
            onValueChanged: (mode) {
              if (mode == null) return;
              setState(() => _draft.timeMode = mode);
            },
          ),
        ),
        _divider(context),
        if (isPeriod) ...[
          _row(
            context: context,
            icon: CupertinoIcons.arrow_right_circle,
            label: '开始节次',
            value: '第 ${_draft.startPeriod} 节',
            onTap: () => _pickPeriod(isStart: true),
          ),
          _divider(context),
          _row(
            context: context,
            icon: CupertinoIcons.arrow_left_circle,
            label: '结束节次',
            value: '第 ${_draft.endPeriod} 节',
            onTap: () => _pickPeriod(isStart: false),
          ),
        ] else ...[
          _row(
            context: context,
            icon: CupertinoIcons.arrow_right_circle,
            label: '开始时刻',
            value: _draft.startClock,
            onTap: () => _pickClock(isStart: true),
          ),
          _divider(context),
          _row(
            context: context,
            icon: CupertinoIcons.arrow_left_circle,
            label: '结束时刻',
            value: _draft.endClock,
            onTap: () => _pickClock(isStart: false),
          ),
        ],
      ],
    );
  }

  /// 节次选择：一个简单的滚轮弹窗（1..maxPeriod）
  Future<void> _pickPeriod({required bool isStart}) async {
    final current = isStart ? _draft.startPeriod : _draft.endPeriod;
    var temp = current;
    final picked = await showCupertinoModalPopup<int>(
      context: context,
      builder: (BuildContext context) => Container(
        height: 260,
        color: CupertinoDynamicColor.resolve(
            CupertinoColors.systemBackground, context),
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  CupertinoButton(
                    child: const Text('取消'),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  Text(isStart ? '开始节次' : '结束节次'),
                  CupertinoButton(
                    child: const Text('确定'),
                    onPressed: () => Navigator.of(context).pop(temp),
                  ),
                ],
              ),
              Expanded(
                child: CupertinoPicker(
                  itemExtent: 40,
                  scrollController: FixedExtentScrollController(
                      initialItem: current - 1),
                  onSelectedItemChanged: (index) => temp = index + 1,
                  children: [
                    for (var i = 1; i <= UserEventDraft.maxPeriod; i++)
                      Center(child: Text('第 $i 节')),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isStart) {
        _draft.startPeriod = picked;
        // 开始节次往后挪过了结束节次时把结束一起带上，省得用户再改一次
        if (_draft.endPeriod < picked) _draft.endPeriod = picked;
      } else {
        _draft.endPeriod = picked;
        if (_draft.startPeriod > picked) _draft.startPeriod = picked;
      }
    });
  }

  /// 颜色那行：一排小圆点，点一下就选
  Widget _colorRow(BuildContext context) {
    final choices = UserEventPalette.choices;
    final selected = _draft.color ?? UserEventPalette.defaultColor;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(
        children: [
          Icon(CupertinoIcons.paintbrush, size: 19, color: AppAccent.primary),
          const SizedBox(width: 12),
          Text('颜色',
              style: TextStyle(
                  fontSize: 16,
                  color: CupertinoDynamicColor.resolve(
                      CupertinoColors.secondaryLabel, context))),
          const Spacer(),
          for (final argb in choices)
            GestureDetector(
              onTap: () => setState(() => _draft.color = argb),
              child: Container(
                margin: const EdgeInsets.only(left: 8),
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: Color(argb),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: argb == selected
                        ? AppAccent.primaryDeep
                        : CupertinoColors.tertiaryLabel,
                    width: argb == selected ? 2.5 : 1,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textColor = CupertinoTheme.of(context).textTheme.textStyle.color;
    final start = _draft.startDate;
    final until = _draft.repeatUntil;

    return CupertinoPageScaffold(
      backgroundColor: pageBackground(context),
      navigationBar: CupertinoNavigationBar(
        backgroundColor: CupertinoDynamicColor.resolve(
            CupertinoColors.systemGroupedBackground, context),
        leading: CupertinoButton(

          padding: EdgeInsets.zero,
          onPressed: () => Navigator.of(context).pop(),
          child: const Icon(CupertinoIcons.xmark),
        ),
        middle: Text(widget.pageTitle),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 编辑既有日程时才给删除入口（新建时没什么可删的）
            if (widget.allowDelete) ...[
              CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: _delete,
                child: const Icon(CupertinoIcons.trash,
                    semanticLabel: '删除'),
              ),
              const SizedBox(width: 14),
            ],
            CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: _canSave ? _save : null,
              child: const Text('保存',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
        border: null,
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(top: 8, bottom: 40),
          children: [
            // 标题
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
              child: CupertinoTextField(
                controller: _titleController,
                placeholder: '比如：学生会例会',
                padding: EdgeInsets.zero,
                decoration: const BoxDecoration(),
                style: TextStyle(
                    fontSize: 28, fontWeight: FontWeight.w700, color: textColor),
                placeholderStyle: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: CupertinoDynamicColor.resolve(
                      CupertinoColors.placeholderText, context),
                ),
                maxLines: null,
              ),
            ),
            const SizedBox(height: 12),

            // 时间
            _timeCard(context),

            const SizedBox(height: 10),
            _card(
              context: context,
              children: [
                _row(
                  context: context,
                  icon: CupertinoIcons.calendar,
                  label: '第一次发生在',
                  value: '${start.month} 月 ${start.day} 日 '
                      '周${_weekdayName(start.weekday)}',
                  onTap: _pickStartDate,
                ),
                _divider(context),
                _row(
                  context: context,
                  icon: CupertinoIcons.repeat,
                  label: '重复',
                  value: _draft.repeatLabel,
                  onTap: _pickRepeat,
                ),
                if (_draft.repeatPeriod != 0) ...[
                  _divider(context),
                  _row(
                    context: context,
                    icon: CupertinoIcons.calendar_badge_minus,
                    label: '重复到',
                    value: until == null
                        ? '一直重复'
                        : '${until.year} 年 ${until.month} 月 ${until.day} 日',
                    onTap: _pickUntil,
                  ),
                  _divider(context),
                  // ===== 这一行必须**对称**（2026-09-25 真机发现）=====
                  //
                  // 原来只有"有结束日期"时才显示「去掉结束日期」，
                  // 用户反馈「点了一下这个选项，它直接消失了」——
                  // 逻辑上没错（清空后那个条件不成立），但操作上是个陷阱：
                  // 点完就**没有回来的路**了（只能靠再点"重复到"重新选一天）。
                  //
                  // 现在两个方向都给出口：有结束日期 → 去掉；没有 → 设置。
                  if (until == null)
                    _row(
                      context: context,
                      icon: CupertinoIcons.calendar_badge_plus,
                      label: '设置结束日期',
                      value: '现在是一直重复',
                      onTap: _pickUntil,
                    )
                  else
                    _row(
                      context: context,
                      icon: CupertinoIcons.clear,
                      label: '去掉结束日期',
                      value: '放假期间也照常发生',
                      onTap: () => setState(() => _draft.repeatUntil = null),
                    ),
                ],
              ],
            ),

            const SizedBox(height: 10),
            _card(
              context: context,
              children: [
                _colorRow(context),
                _divider(context),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: Row(
                    children: [
                      Icon(CupertinoIcons.location,
                          size: 19, color: AppAccent.primary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: CupertinoTextField(
                          controller: _locationController,
                          placeholder: '地点（可留空）',
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: const BoxDecoration(),
                          style: TextStyle(fontSize: 16, color: textColor),
                        ),
                      ),
                    ],
                  ),
                ),
                _divider(context),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Icon(CupertinoIcons.text_alignleft,
                            size: 19, color: AppAccent.primary),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: CupertinoTextField(
                          controller: _noteController,
                          placeholder: '备注（可留空）',
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: const BoxDecoration(),
                          style: TextStyle(fontSize: 16, color: textColor),
                          maxLines: null,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: Text(
                // 说清这条日程的行为，免得用户以为它会跟着放假挪
                '自定义日程按"周几 + 重复间隔"排，不跟校历的假期与调休走：'
                '放假那天的例会不会自动消失，需要你自己改结束日期或删掉。',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.5,
                  color: CupertinoDynamicColor.resolve(
                      CupertinoColors.tertiaryLabel, context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _weekdayName(int weekday) =>
      const ['一', '二', '三', '四', '五', '六', '日'][(weekday - 1) % 7];
}

/// 新建日程时用的默认草稿（今天、按时刻 19:00-20:30、每周）。
///
/// 为什么默认"按时刻"而不是"按节次"：这个功能的首个场景是学生组织例会，
/// 那种事是按钟点定的（19:00 开会），而不是按第几节课。
///
/// [semesterLastDay] 非空时，**重复截止日预填成那一天**（SPEC.md D11）：
/// 这样"上学期的例会不会带到下学期"不用额外机制就成立；
/// 用户可以在编辑页里清掉它（清掉 = 一直重复，放假期间照常发生）。
UserEventDraft newUserEventDraft({
  DateTime? today,
  String? semesterName,
  DateTime? semesterLastDay,
}) {
  final now = today ?? DateTime.now();
  return UserEventDraft(
    title: '',
    startDate: DateTime(now.year, now.month, now.day),
    timeMode: UserEventTimeMode.clock,
    startClock: '19:00',
    endClock: '20:30',
    repeatPeriod: 1,
    repeatUntil: semesterLastDay == null
        ? null
        : DateTime(
            semesterLastDay.year, semesterLastDay.month, semesterLastDay.day),
    semesterName: semesterName,
    color: UserEventPalette.defaultColor,
  );
}
