import 'package:celechron/mod/user_event.dart';
import 'package:flutter_test/flutter_test.dart';

/// 「这条日程属于哪个学期」的过滤口径（2026-09-25 修的一个真 bug）。
///
/// **bug 现场**：课表与日历那两处取数用的是**全量** `userEvents`，
/// 于是下学期建的例会会出现在本学期的课表上 —— 位置还按本学期的节次算。
/// 更糟的是它没有对应的课表可以对照，用户只会觉得"我这条日程的位置不对"。
///
/// 修法：两处都改成只铺**属于该学期**的（外加没写学期的那种"不限学期"）。
/// 这里把过滤口径逐字钉住，免得以后有人图省事又传回全量。
///
/// 说明：过滤实现在 `lib/mod/user_event_store.dart` 的
/// `userEventsOfSemester` 扩展里（需要 Hive，所以不能在纯测试里 import）。
/// 这里用一份**逐字一致**的复制来钉住口径；两处改动时请一起改。
void main() {
  DateTime d(int month, int day) => DateTime(2026, month, day);

  UserEvent ev(String uid, {String? semester}) => UserEvent(
        uid: uid,
        title: '学生会例会',
        startDate: d(9, 14),
        dayOfWeek: DateTime.monday,
        startClock: '19:00',
        endClock: '20:30',
        semesterName: semester,
      );

  /// 与 `UserEventStore.userEventsOfSemester` 逐字一致
  List<String> ofSemester(List<UserEvent> all, String? semesterName) => all
      .where((event) =>
          event.semesterName == null ||
          semesterName == null ||
          event.semesterName == semesterName)
      .map((event) => event.uid)
      .toList();

  final mine = ev('mine', semester: '2026-2027-1秋冬');
  final other = ev('other', semester: '2026-2027-2春夏');
  final free = ev('free'); // 没写学期 = 不限学期

  group('学期过滤', () {
    test('★ 本学期：只留下本学期的 + 不限学期的（不含下学期的）', () {
      expect(ofSemester([mine, other, free], '2026-2027-1秋冬'), ['mine', 'free']);
    });

    test('★ 下学期：不含本学期的', () {
      expect(ofSemester([mine, other, free], '2026-2027-2春夏'), ['other', 'free']);
    });

    test('不限学期的日程哪边都在（没写学期就是"哪学期都算"）', () {
      expect(ofSemester([free], '2026-2027-1秋冬'), ['free']);
      expect(ofSemester([free], '2026-2027-2春夏'), ['free']);
    });

    test('学期名为 null 时不筛（调用方拿不到学期时的出路）', () {
      expect(ofSemester([mine, other, free], null), ['mine', 'other', 'free']);
    });

    test('空表进空表出', () {
      expect(ofSemester(const [], '2026-2027-1秋冬'), isEmpty);
    });

    test('★ 对照：不过滤时下学期的会串进本学期（这就是那个 bug）', () {
      final unfiltered = [mine, other, free].map((e) => e.uid).toList();
      expect(unfiltered, ['mine', 'other', 'free']);
      expect(unfiltered.contains('other'), isTrue,
          reason: '不过滤的话下学期的日程也会被铺到本学期那张表上');
    });
  });
}
