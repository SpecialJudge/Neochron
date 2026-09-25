import 'package:celechron/mod/user_event.dart';
import 'package:celechron/mod/user_event_rule.dart';
import 'package:flutter_test/flutter_test.dart';

/// 自定义日程的「发生判定」（SPEC.md 3.3 / D3 / D11）。
///
/// 这一套判定是整个功能的**地基**：它算错一天，用户在课表和日历上就会
/// 看到错误的例会。所以这里把每一条口径都钉住，尤其是三处最容易改错的：
///
/// 1. **「每两周」的奇偶基准取自 `startDate`**，不是"校历奇数周"；
/// 2. **`repeatUntil` 为 null 表示没有终点**（D11 允许清空），
///    不许偷偷给它补一个"到学期末"的默认值；
/// 3. **假期与调休一律不影响判定**（D6），这条是刻意不做，不是漏做。
void main() {
  /// 2026-09-14 是**周一**（2026 年的第 38 周）。下面所有用例都以它为基准。
  DateTime d(int month, int day) => DateTime(2026, month, day);

  /// 一条"每周一次"的日程：从给定日期开始，按节次排（第 5-6 节）
  UserEvent weekly(
    DateTime start, {
    int period = 1,
    DateTime? until,
    String title = '学生会例会',
  }) {
    return UserEvent(
      uid: 'uid-${start.toIso8601String()}',
      title: title,
      startDate: start,
      dayOfWeek: start.weekday,
      startPeriod: 5,
      endPeriod: 6,
      repeatPeriod: period,
      repeatUntil: until,
      location: '紫金港小剧场',
    );
  }

  group('星期几：不匹配的日期一律不发生', () {
    test('从周一开始的日程，周二不发生', () {
      final e = weekly(d(9, 14));
      expect(UserEventRule.occursOn(e, d(9, 15)), isFalse);
    });

    test('同一个星期的其它天都不发生，只有那天发生', () {
      final e = weekly(d(9, 14));
      for (var offset = 0; offset < 7; offset++) {
        final day = d(9, 14).add(Duration(days: offset));
        expect(
          UserEventRule.occursOn(e, day),
          offset == 0,
          reason: '第 $offset 天（${day.weekday}）判定错了',
        );
      }
    });
  });

  group('起点：第一次发生的日期之前都不发生', () {
    test('开始日的前一周不发生（哪怕星期几正好对上）', () {
      final e = weekly(d(9, 14));
      expect(UserEventRule.occursOn(e, d(9, 7)), isFalse);
    });

    test('开始日之前、且间隔正好是整数周的那天，也不发生', () {
      final e = weekly(d(9, 14));
      // 9/14 往前 4 周是 8/17，每周一次的话"上周一"也不该有
      expect(UserEventRule.occursOn(e, d(8, 17)), isFalse);
    });
  });

  group('每周（repeatPeriod = 1）', () {
    test('开始日当天发生', () {
      expect(UserEventRule.occursOn(weekly(d(9, 14)), d(9, 14)), isTrue);
    });

    test('之后每个周一都发生', () {
      final e = weekly(d(9, 14));
      for (final day in [d(9, 21), d(9, 28), d(10, 5), d(11, 16)]) {
        expect(UserEventRule.occursOn(e, day), isTrue, reason: '$day 应该发生');
      }
    });

    test('跨年也算得对（2026-12-28 到 2027-01-04）', () {
      final e = weekly(d(9, 14));
      expect(UserEventRule.occursOn(e, DateTime(2026, 12, 28)), isTrue);
      expect(UserEventRule.occursOn(e, DateTime(2027, 1, 4)), isTrue);
      expect(UserEventRule.occursOn(e, DateTime(2027, 1, 5)), isFalse);
    });
  });

  group('每两周（repeatPeriod = 2）：奇偶基准取自 startDate', () {
    test('9/14 开始 → 9/28 发生、9/21 不发生', () {
      final e = weekly(d(9, 14), period: 2);
      expect(UserEventRule.occursOn(e, d(9, 14)), isTrue);
      expect(UserEventRule.occursOn(e, d(9, 21)), isFalse, reason: '隔一周，不该有');
      expect(UserEventRule.occursOn(e, d(9, 28)), isTrue);
    });

    test('再往后一轮也保持同一奇偶（10/12 发生、10/19 不发生）', () {
      final e = weekly(d(9, 14), period: 2);
      expect(UserEventRule.occursOn(e, d(10, 12)), isTrue);
      expect(UserEventRule.occursOn(e, d(10, 19)), isFalse);
    });

    test('★ 换一个起点，奇偶跟着换（9/21 开始 → 9/28 就不发生了）', () {
      final e = weekly(d(9, 21), period: 2);
      expect(UserEventRule.occursOn(e, d(9, 21)), isTrue);
      expect(UserEventRule.occursOn(e, d(9, 28)), isFalse);
      expect(UserEventRule.occursOn(e, d(10, 5)), isTrue);
    });
  });

  group('每 N 周（repeatPeriod = 3 / 4）', () {
    test('每三周：9/14、10/5、10/26 发生，中间不发生', () {
      final e = weekly(d(9, 14), period: 3);
      expect(UserEventRule.occursOn(e, d(9, 14)), isTrue);
      expect(UserEventRule.occursOn(e, d(9, 21)), isFalse);
      expect(UserEventRule.occursOn(e, d(9, 28)), isFalse);
      expect(UserEventRule.occursOn(e, d(10, 5)), isTrue);
      expect(UserEventRule.occursOn(e, d(10, 26)), isTrue);
      expect(UserEventRule.occursOn(e, d(11, 2)), isFalse);
    });

    test('每四周：一个月一次那种', () {
      final e = weekly(d(9, 14), period: 4);
      expect(UserEventRule.occursOn(e, d(10, 12)), isTrue);
      expect(UserEventRule.occursOn(e, d(10, 5)), isFalse);
    });
  });

  group('只这一次（repeatPeriod = 0）', () {
    test('★ 只有开始日那天发生，下一周不发生（真实 bug 回归）', () {
      // 这条是**真抓到过的 bug**：原来写成 `if (!isSingleOccurrence) { 检查整周差 }`，
      // 于是 repeatPeriod = 0 时整段检查被跳过、又没有截止日拦着，
      // 「只这一次」被当成了「每周」。改动判定时务必保留这一条。
      final e = weekly(d(9, 14), period: 0);
      expect(UserEventRule.occursOn(e, d(9, 14)), isTrue);
      expect(UserEventRule.occursOn(e, d(9, 21)), isFalse);
      expect(UserEventRule.occursOn(e, d(10, 5)), isFalse);
    });

    test('★ 一年后的同一天也不发生（别只在"下一周"上打补丁）', () {
      final e = weekly(d(9, 14), period: 0);
      expect(UserEventRule.occursOn(e, DateTime(2027, 9, 14)), isFalse);
      expect(UserEventRule.occursOn(e, DateTime(2026, 9, 14)), isTrue);
    });

    test('★ 扫一整年，只应该扫出一天', () {
      final e = weekly(d(9, 14), period: 0);
      final got = UserEventRule.occurrencesBetween(
        e,
        DateTime(2026, 9, 1),
        DateTime(2027, 8, 31),
      );
      expect(got, [d(9, 14)], reason: '只这一次的日程，一年里只能有一天');
    });

    test('isSingleOccurrence / lastDay 的说法一致', () {
      final e = weekly(d(9, 14), period: 0);
      expect(e.isSingleOccurrence, isTrue);
      expect(e.lastDay, d(9, 14));
    });

    test('负数的 repeatPeriod 也当作只这一次', () {
      final e = weekly(d(9, 14), period: -3);
      expect(e.isSingleOccurrence, isTrue);
      expect(UserEventRule.occursOn(e, d(9, 14)), isTrue);
      expect(UserEventRule.occursOn(e, d(9, 21)), isFalse);
    });
  });

  group('截止日 repeatUntil（D11：null = 没有终点）', () {
    test('★ 为 null 时**一直重复**，不给它偷偷加"到学期末"的默认值', () {
      final e = weekly(d(9, 14));
      expect(e.repeatUntil, isNull);
      expect(UserEventRule.occursOn(e, d(9, 14)), isTrue);
      expect(UserEventRule.occursOn(e, DateTime(2027, 3, 1)), isTrue,
          reason: '半年后仍然应该发生（用户清空截止日就是为了放假也能用）');
      expect(e.lastDay, isNull);
    });

    test('截止日**含端点当天**', () {
      // 10/2 是周五；这条日程是周一，所以把截止日设成 10/5（周一）才是"含端点"
      final e = weekly(d(9, 14), until: d(10, 5));
      expect(UserEventRule.occursOn(e, d(10, 5)), isTrue, reason: '截止日当天要算');
      expect(UserEventRule.occursOn(e, d(10, 12)), isFalse, reason: '过一天就不算');
    });

    test('截止日落在两个发生日之间时，下一个发生日不再算', () {
      final e = weekly(d(9, 14), until: d(10, 2)); // 周五截止
      expect(UserEventRule.occursOn(e, d(9, 28)), isTrue);
      expect(UserEventRule.occursOn(e, d(10, 5)), isFalse);
    });

    test('截止日早于开始日 → 一次都不发生', () {
      final e = weekly(d(9, 14), until: d(9, 1));
      expect(UserEventRule.occursOn(e, d(9, 14)), isFalse);
      expect(e.lastDay, d(9, 1));
    });
  });

  group('假期与调休：一条都不影响判定（D6，刻意不做）', () {
    test('10/1 国庆当天，照常判定为发生', () {
      // 2026-10-01 是周四；这条日程是周一，所以换成 10/5（周一，假期内）
      final e = weekly(d(9, 14));
      expect(UserEventRule.occursOn(e, d(10, 5)), isTrue,
          reason: '放假那天的例会不会自动消失，要用户自己删（SPEC.md D6 的代价）');
    });
  });

  group('自洽校验：dayOfWeek 与 startDate 不一致时以 startDate 为准', () {
    test('★ 传错周几会被自动纠正，不会出现"永远不发生"的静默故障', () {
      final e = UserEvent(
        uid: 'u1',
        title: '手工测试',
        startDate: d(9, 14), // 周一
        dayOfWeek: 3, // 故意写错成周三
        startPeriod: 5,
      );
      expect(e.dayOfWeek, DateTime.monday);
      expect(UserEventRule.occursOn(e, d(9, 14)), isTrue);
      expect(UserEventRule.occursOn(e, d(9, 16)), isFalse);
    });

    test('startDate 带时分秒时只取日期部分', () {
      final e = UserEvent(
        uid: 'u1',
        title: '手工测试',
        startDate: DateTime(2026, 9, 14, 23, 59, 30),
        dayOfWeek: 1,
        startPeriod: 5,
      );
      expect(e.startDate, d(9, 14));
      expect(e.startDate.hour, 0);
      expect(UserEventRule.occursOn(e, d(9, 14)), isTrue);
    });

    test('repeatUntil 带时分秒时也只取日期部分', () {
      final e = weekly(d(9, 14), until: DateTime(2026, 10, 5, 23, 59));
      expect(e.repeatUntil, d(10, 5));
      expect(UserEventRule.occursOn(e, d(10, 5)), isTrue);
    });
  });

  group('occurrencesBetween：扫一段日期', () {
    test('含两端，按升序', () {
      final e = weekly(d(9, 14));
      final got = UserEventRule.occurrencesBetween(e, d(9, 14), d(10, 12));
      expect(got, [d(9, 14), d(9, 21), d(9, 28), d(10, 5), d(10, 12)]);
    });

    test('区间端点本身不是发生日时不会硬塞进来', () {
      final e = weekly(d(9, 14));
      final got = UserEventRule.occurrencesBetween(e, d(9, 15), d(9, 20));
      expect(got, isEmpty);
    });

    test('区间反过来传 → 空表，不抛异常', () {
      final e = weekly(d(9, 14));
      expect(UserEventRule.occurrencesBetween(e, d(10, 12), d(9, 14)), isEmpty);
    });

    test('周日到跨月的边界（2 月 28 日 → 3 月 1 日）不越界', () {
      // 2027-03-01 是周一
      final e = weekly(DateTime(2027, 3, 1));
      final got = UserEventRule.occurrencesBetween(
        e,
        DateTime(2027, 2, 28),
        DateTime(2027, 3, 1),
      );
      expect(got, [DateTime(2027, 3, 1)]);
    });
  });

  group('nextOccurrence：找下一次', () {
    test('当天就是发生日 → 返回当天', () {
      final e = weekly(d(9, 14));
      expect(UserEventRule.nextOccurrence(e, d(9, 14)), d(9, 14));
    });

    test('从周三问 → 返回下周一', () {
      final e = weekly(d(9, 14));
      expect(UserEventRule.nextOccurrence(e, d(9, 16)), d(9, 21));
    });

    test('没有终点的日程，一年内也找得到', () {
      final e = weekly(d(9, 14));
      expect(UserEventRule.nextOccurrence(e, DateTime(2027, 5, 3)),
          DateTime(2027, 5, 3)); // 2027-05-03 也是周一
    });

    test('已经过了截止日 → null', () {
      final e = weekly(d(9, 14), until: d(10, 5));
      expect(UserEventRule.nextOccurrence(e, d(10, 6)), isNull);
    });

    test('只这一次且已过去 → null', () {
      final e = weekly(d(9, 14), period: 0);
      expect(UserEventRule.nextOccurrence(e, d(9, 15)), isNull);
    });

    test('开始日之前去问 → 返回开始日', () {
      final e = weekly(d(9, 14));
      expect(UserEventRule.nextOccurrence(e, d(9, 1)), d(9, 14));
    });
  });

  group('序列化往返（以后要进 Hive 与同步包）', () {
    test('每个字段都能原样回来', () {
      final e = UserEvent(
        uid: 'uid-1',
        title: '学生会例会',
        startDate: d(9, 14),
        dayOfWeek: 1,
        startPeriod: 5,
        endPeriod: 6,
        repeatPeriod: 2,
        repeatUntil: d(12, 21),
        semesterName: '2026-2027-1秋冬',
        location: '紫金港小剧场',
        note: '带水杯',
        color: 0xFFFF00FF,
        reminderEnabled: true,
        reminderLeadMinutes: 15,
        createdAt: DateTime(2026, 9, 25, 10, 0),
        updatedAt: DateTime(2026, 9, 25, 11, 0),
      );

      final back = UserEvent.fromMap(e.toMap())!;
      expect(back.uid, e.uid);
      expect(back.title, e.title);
      expect(back.startDate, e.startDate);
      expect(back.dayOfWeek, e.dayOfWeek);
      expect(back.startPeriod, e.startPeriod);
      expect(back.endPeriod, e.endPeriod);
      expect(back.repeatPeriod, e.repeatPeriod);
      expect(back.repeatUntil, e.repeatUntil);
      expect(back.semesterName, e.semesterName);
      expect(back.location, e.location);
      expect(back.note, e.note);
      expect(back.color, e.color);
      expect(back.reminderEnabled, e.reminderEnabled);
      expect(back.reminderLeadMinutes, e.reminderLeadMinutes);
      expect(back.createdAt, e.createdAt);
      expect(back.updatedAt, e.updatedAt);
    });

    test('按具体时刻那种也能往返', () {
      final e = UserEvent(
        uid: 'uid-2',
        title: '家教',
        startDate: d(9, 16),
        dayOfWeek: 3,
        startClock: '19:00',
        endClock: '20:30',
        repeatPeriod: 1,
      );
      final back = UserEvent.fromMap(e.toMap())!;
      expect(back.usesPeriod, isFalse);
      expect(back.startClock, '19:00');
      expect(back.endClock, '20:30');
      expect(back.timeLabel, '19:00-20:30');
    });

    test('缺 uid / 缺开始时间 → 返回 null（调用方据此丢掉这条）', () {
      expect(UserEvent.fromMap(null), isNull);
      expect(UserEvent.fromMap(<String, dynamic>{}), isNull);
      expect(
        UserEvent.fromMap(<String, dynamic>{
          'uid': 'u1',
          'title': '没开始时间',
          'startPeriod': 5,
        }),
        isNull,
      );
    });

    test('★ 既没有节次也没有时刻 → 返回 null（排不了版，不能装作能显示）', () {
      expect(
        UserEvent.fromMap(<String, dynamic>{
          'uid': 'u1',
          'title': '两头都缺',
          'startDate': d(9, 14).millisecondsSinceEpoch,
        }),
        isNull,
      );
    });

    test('repeatPeriod 缺失时按 1（每周）兜底', () {
      final back = UserEvent.fromMap(<String, dynamic>{
        'uid': 'u1',
        'title': '老数据',
        'startDate': d(9, 14).millisecondsSinceEpoch,
        'startPeriod': 5,
      })!;
      expect(back.repeatPeriod, 1);
      expect(back.repeatUntil, isNull);
    });
  });

  group('给人看的说法', () {
    test('每周 vs 每两周 vs 只这一次', () {
      expect(weekly(d(9, 14)).repeatLabel, '每周一');
      expect(weekly(d(9, 14), period: 2).repeatLabel, '每 2 周的周一');
      expect(weekly(d(9, 14), period: 0).repeatLabel, '仅 9 月 14 日（周一）');
    });

    test('按节次与按时刻的时间说法', () {
      expect(weekly(d(9, 14)).timeLabel, '第 5-6 节');
      expect(
        UserEvent(
          uid: 'u',
          title: 't',
          startDate: d(9, 14),
          dayOfWeek: 1,
          startClock: '19:00',
        ).timeLabel,
        '19:00',
      );
    });
  });

  group('copyWith', () {
    test('改开始日期时周几跟着变', () {
      final e = weekly(d(9, 14));
      final moved = e.copyWith(startDate: d(9, 16)); // 周三
      expect(moved.dayOfWeek, DateTime.wednesday);
      expect(UserEventRule.occursOn(moved, d(9, 16)), isTrue);
      expect(UserEventRule.occursOn(moved, d(9, 14)), isFalse);
    });

    test('★ 清空截止日要用 clearRepeatUntil（传 null 表示"不改"）', () {
      final e = weekly(d(9, 14), until: d(10, 5));
      expect(e.copyWith().repeatUntil, d(10, 5));
      expect(e.copyWith(clearRepeatUntil: true).repeatUntil, isNull);
    });

    test('updatedAt 会自动刷新，createdAt 不动', () {
      final e = weekly(d(9, 14));
      final later = e.copyWith(title: '改个名');
      expect(later.title, '改个名');
      expect(later.createdAt, e.createdAt);
      expect(later.updatedAt.isBefore(e.updatedAt), isFalse);
    });
  });
}
