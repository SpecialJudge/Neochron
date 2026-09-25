import 'package:celechron/model/period.dart';
import 'package:celechron/model/semester.dart';
import 'package:celechron/page/calendar/calendar_controller.dart';
import 'package:flutter_test/flutter_test.dart';

/// 「某一天属于哪个学期」的判定（`semesterContaining`，给自定义日程用）。
///
/// 为什么单独锁这一条：自定义日程要知道"这一天该用哪个学期的节次换算表"，
/// 而**没套过校历的学期**必须被排除 —— 那种学期的 `firstDay` / `lastDay`
/// 返回的是求值那一刻的现在，拿它判断会把任意一天都算成在学期内
/// （`getUpcomingSemester` 的注释里记过同一个坑，实测出现过张冠李戴的标题）。
///
/// 真的 `Semester` 要从一堆私有字段与 Hive 里长出来，测试里不值当构造，
/// 所以用一个只填了必要 getter 的假的：`semesterContaining` 只读这几个。
class _FakeSemester extends Semester {
  _FakeSemester({
    required String name,
    required DateTime first,
    required DateTime last,
    required this.fakeHasCalendar,
  })  : _first = first,
        _last = last,
        super(name);

  final DateTime _first;
  final DateTime _last;
  final bool fakeHasCalendar;

  @override
  bool get hasCalendar => fakeHasCalendar;

  @override
  DateTime get firstDay => _first;

  @override
  DateTime get lastDay => _last;

  @override
  List<Period> get periods => const <Period>[];

  /// 学期名形如 `2026-2027-1秋冬`（构造时要按这个格式取字符，所以给全 11 位以上）
  static _FakeSemester one(String name, DateTime first, DateTime last,
          {bool hasCalendar = true}) =>
      _FakeSemester(
          name: name, first: first, last: last, fakeHasCalendar: hasCalendar);
}

void main() {
  DateTime d(int month, int day) => DateTime(2026, month, day);

  _FakeSemester autumn() => _FakeSemester.one(
        '2026-2027-1秋冬',
        d(9, 14),
        DateTime(2027, 1, 24),
      );

  _FakeSemester spring() => _FakeSemester.one(
        '2026-2027-2春夏',
        DateTime(2027, 2, 22),
        DateTime(2027, 7, 4),
      );

  group('落在哪个学期', () {
    test('学期内的某天 → 那个学期', () {
      expect(semesterContaining([autumn()], d(9, 14))?.name, '2026-2027-1秋冬');
      expect(semesterContaining([autumn()], d(11, 3))?.name, '2026-2027-1秋冬');
      expect(semesterContaining([autumn()], DateTime(2027, 1, 24))?.name,
          '2026-2027-1秋冬');
    });

    test('第一天与最后一天都算在内（含端点）', () {
      expect(semesterContaining([autumn()], d(9, 14)), isNotNull);
      expect(semesterContaining([autumn()], DateTime(2027, 1, 24)), isNotNull);
    });

    test('早一天 / 晚一天都不算', () {
      expect(semesterContaining([autumn()], d(9, 13)), isNull);
      expect(semesterContaining([autumn()], DateTime(2027, 1, 25)), isNull);
    });

    test('两个学期之间（寒假）→ null', () {
      final semesters = [autumn(), spring()];
      expect(semesterContaining(semesters, DateTime(2027, 2, 1)), isNull);
    });

    test('多个学期时各归各的', () {
      final semesters = [autumn(), spring()];
      expect(semesterContaining(semesters, d(10, 1))?.name, '2026-2027-1秋冬');
      expect(semesterContaining(semesters, DateTime(2027, 3, 1))?.name,
          '2026-2027-2春夏');
    });

    test('空列表 → null', () {
      expect(semesterContaining(const <Semester>[], d(10, 1)), isNull);
    });

    test('★ 没套过校历的学期必须被跳过（否则会把任意一天都算成学期内）', () {
      final noCalendar = _FakeSemester.one(
        '2026-2027-2春夏',
        DateTime(2027, 2, 22),
        DateTime(2027, 7, 4),
        hasCalendar: false,
      );
      expect(semesterContaining([noCalendar], DateTime(2027, 3, 1)), isNull);
      // 有校历的那个仍然能找到
      expect(semesterContaining([noCalendar, autumn()], d(10, 1))?.name,
          '2026-2027-1秋冬');
    });

    test('时分秒不影响判定（只比日期）', () {
      expect(
        semesterContaining([autumn()], DateTime(2026, 9, 14, 23, 59, 59)),
        isNotNull,
      );
      expect(
        semesterContaining([autumn()], DateTime(2026, 9, 13, 23, 59, 59)),
        isNull,
      );
    });
  });
}
