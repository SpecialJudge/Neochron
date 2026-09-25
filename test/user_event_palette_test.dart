import 'package:celechron/design/user_event_palette.dart';
import 'package:celechron/mod/user_event_periods.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

/// 自定义日程的颜色预设（`lib/design/user_event_palette.dart`，SPEC.md R3）。
///
/// 口径：课表里课程走时段色阶（按小时从红变到紫），日程**一律固定色**，
/// 两类不共用调色板 —— 否则 20 点的例会（品红档）会和 8 点的课（红档）撞色。
void main() {
  group('默认色就是爱莉粉，且全仓只有一处定义', () {
    test('默认色 = UserEventCalendar.eventColorArgb = #FFA6C9', () {
      expect(UserEventPalette.defaultColor, 0xFFFFA6C9);
      expect(UserEventPalette.defaultColor, UserEventCalendar.eventColorArgb);
    });

    test('choices 第一项就是默认色（默认值不会是别的颜色）', () {
      expect(UserEventPalette.choices.first, UserEventPalette.defaultColor);
    });

    test('choices 里没有重复色', () {
      final list = UserEventPalette.choices;
      expect(list.toSet().length, list.length);
    });

    test('choices 至少有 3 个可选（用户得有得挑）', () {
      expect(UserEventPalette.choices.length, greaterThanOrEqualTo(3));
    });
  });

  group('按名字查', () {
    test('默认色叫爱莉粉', () {
      expect(UserEventPalette.nameOf(UserEventPalette.defaultColor), '爱莉粉');
    });

    test('备选色认得出来（天依蓝来自闹钟配色预设）', () {
      expect(UserEventPalette.nameOf(0xFF66CCFF), '天依蓝');
    });

    test('不认识的色返回空串（不硬编一个名字）', () {
      expect(UserEventPalette.nameOf(0xFF123456), '');
    });
  });

  group('resolve：存的值 -> 实际画的颜色', () {
    test('null → 默认色（老数据没有这个字段时的出路）', () {
      expect(UserEventPalette.resolve(null), const Color(0xFFFFA6C9));
    });

    test('认识的色原样返回', () {
      expect(UserEventPalette.resolve(0xFF66CCFF), const Color(0xFF66CCFF));
    });

    test('★ 不认识的色回退到默认色，而不是原样用', () {
      // 原样用可能画成透明或纯黑，用户会以为日程丢了
      expect(
        UserEventPalette.resolve(0xFF123456),
        const Color(0xFFFFA6C9),
      );
    });
  });

  group('next：点一下换一个色', () {
    test('从默认色出发拿到第二个可选色（不是它自己）', () {
      final nxt = UserEventPalette.next(null);
      expect(nxt, isNot(UserEventPalette.defaultColor));
      expect(UserEventPalette.choices.contains(nxt), isTrue);
    });

    test('走到最后一个绕回第一个', () {
      final list = UserEventPalette.choices;
      expect(UserEventPalette.next(list.last), list.first);
    });

    test('全部走一圈能回到起点（不会卡住或漏掉）', () {
      var current = UserEventPalette.defaultColor;
      final seen = <int>{current};
      for (var i = 0; i < UserEventPalette.choices.length - 1; i++) {
        current = UserEventPalette.next(current);
        seen.add(current);
      }
      expect(seen.length, UserEventPalette.choices.length);
      expect(UserEventPalette.next(current), UserEventPalette.defaultColor);
    });

    test('存了一个不认识的色时从头开始', () {
      expect(UserEventPalette.next(0xFF123456), UserEventPalette.choices.first);
    });
  });
}
