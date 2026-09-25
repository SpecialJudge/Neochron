import 'package:celechron/design/alarm_theme.dart' show kAlarmThemes;
import 'package:celechron/mod/user_event_periods.dart' show UserEventCalendar;
import 'package:flutter/cupertino.dart';

/// ============ 自定义日程的颜色预设（SPEC.md R3）============
///
/// 课表格子里的课程走**时段色阶**（`TimeColors.colorFromHour`，按小时从红变到紫），
/// 自定义日程**一律用固定色**，两类不共用调色板 —— 否则 20 点的例会（品红档）
/// 与 8 点的课（红档）会撞色，粉色的区分意义就没了。
///
/// 默认色**不在这里重新定义**：它就是
/// [UserEventCalendar.eventColorArgb]（`#FFA6C9`），
/// 而那个值来自仓库里已有的「爱莉粉」预设（`lib/design/alarm_theme.dart`，
/// 与 `assets/logo.png` 同一色系），所以整套下来**没有新增任何颜色常量**。
///
/// 备选色直接用闹钟配色那四个预设的主色：用户在设置里已经见过它们，
/// 不再另造一套色板。**粉色固定排第一**，也就是默认值。
class UserEventPalette {
  const UserEventPalette._();

  /// 默认色（爱莉粉 `#FFA6C9`）。唯一来源是 [UserEventCalendar.eventColorArgb]。
  static int get defaultColor => UserEventCalendar.eventColorArgb;

  /// 可选颜色（ARGB）。第一项是默认色。
  static List<int> get choices => [
        defaultColor,
        for (final theme in kAlarmThemes)
          // 爱莉粉已经在第一位，别重复
          if (theme.primary.toARGB32() != defaultColor) theme.primary.toARGB32(),
      ];

  /// 想按名字显示时用（找不到就返回空串）
  static String nameOf(int argb) {
    if (argb == defaultColor) return '爱莉粉';
    for (final theme in kAlarmThemes) {
      if (theme.primary.toARGB32() == argb) return theme.name;
    }
    return '';
  }

  /// 存下来的颜色 -> 实际要画的颜色。
  ///
  /// **存的值不认识时回退到默认色**，而不是原样用：那样至少还能看见，
  /// 不会是透明或者纯黑（这也是 `AlarmTheme` 那边 `alarmThemeOf` 的口径）。
  static Color resolve(int? stored) {
    if (stored == null) return Color(defaultColor);
    if (choices.contains(stored)) return Color(stored);
    return Color(defaultColor);
  }

  /// 给"点一下换一个颜色"这种交互用：返回下一个可选色（到头绕回第一个）。
  static int next(int? current) {
    final list = choices;
    if (list.isEmpty) return defaultColor;
    final index = list.indexOf(current ?? defaultColor);
    if (index < 0) return list.first;
    return list[(index + 1) % list.length];
  }
}
