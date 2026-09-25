/// 取日期部分（本地时区的 00:00）。
///
/// ============ 为什么单独开一个文件 ============
///
/// 这个功能的地基是**纯逻辑**（发生判定），必须能脱离 Flutter 环境单测。
/// 而仓库里已有的 `dateOnly`（`lib/utils/utils.dart`）所在的那个文件
/// import 了 `flutter/foundation.dart` 与 `flutter_secure_storage`，
/// 一旦引进来，`dart test` 会在加载 secure_storage 时直接失败
/// （实测过：这也是把规则写成纯 Dart 的意义所在）。
///
/// 又不愿意在两个文件里各写一份：那样会形成
/// `user_event.dart` 与 `user_event_rule.dart` **互相 import** 的循环，
/// 两个同名的顶层函数还会在同时 import 两者的文件里撞成 ambiguous import
/// （临时验证程序就当场编译失败了）。
///
/// 所以放成一个谁都不依赖的叶子文件，两边都 import 它。
///
/// 行为与 `utils/utils.dart` 的 `dateOnly` **完全一致**（都是 `DateTime(y, m, d)`）。
library;

DateTime userEventDateOnly(DateTime date) =>
    DateTime(date.year, date.month, date.day);
