# Neochron 工作清单

> **这份是当前唯一在用的清单。** 新东西一律加在这里。
>
> - Elychron 时代那份（到 v1.4.2 计划为止）已归档到
>   [BACKLOG-DEPRECATED.md](BACKLOG-DEPRECATED.md)，**只读、不再维护**。
>   它的编号（`#13` `#20` `#24` `#28` `#29.x`）仍然有效，代码注释里指向的就是它。
> - **本清单重新编号，从 #1 开始**，不续用旧编号。
> - 从旧清单捡起某条时，在本文件里**新登记一次**，注明「出自旧清单 #NN」。
>
> 已经做完的事写在 [MOD_NOTES.md](../MOD_NOTES.md)；设计文档在
> [SPEC.md](../SPEC.md)（当前是日程自定义）。

## 登记规则

1. **一条一件事**，写清「要什么 / 为什么现在不做（若挂起）/ 什么条件下该做」，
   避免以后想不起来当时的判断 —— 这是旧清单最有价值的部分，照搬。
2. 进行中的条目要写**分支名**和**验证方式**；AGENTS.md 要求一个功能一个分支。
3. 做完立刻挪到「已收口」，写明**改了哪些文件 + 验证结果**，别让它烂在中间状态。
4. 涉及数据库 schema 的改动，必须同步 `docs/DB_SCHEMA.md`（该文件目前**尚不存在**，
   见 I2）并说明迁移策略 —— 这是 AGENTS.md 第 5 条的硬性要求。

---

# 一、进行中

## #1 日程自定义：在课表之上加自己的事（学生组织例会等）

- **来源**：用户 2026-09-25 直接指定。**明确不走旧清单的既有条目。**
- **设计文档**：[SPEC.md](../SPEC.md)（需求 R1-R9 + 10 项拍板 D1-D10，用户已给意见）
- **拍板结论**：D1 新实体、D2 `+` 弹选择、**D3 按自然周几 + 截止日（用户改的）**、
  D4 两种时间口径都支持、D5 第一期不做提醒、D6 假期不动调休跟着走、
  D7 先只做整条删、D8 不做点空白新建、D9 第二期、D10 叠加显示不自动调整。
  R3 补充：**自定义日程在课表里统一用粉色，与课程的时段色阶区分开。**
- **状态**：**七步全部完成并提交**；用户全量 `flutter test` **861 个用例全过**。
  - 代码与文档都已落地，`dart analyze` 0 error；
  - **只剩真机验收**（手机已连上，`adb devices` 能看到 `R5GL50QSPBE`）。
    步骤见 `tools/manual_check_user_event.md`。
  - ⚠️ **装上去之前先看签名**：手机上现装的 `xyz.nosig.celechron.mod`
    是 1.4.1-elychron.1、签名 `9dfef6e0`（**上一台机器的调试密钥**），
    而本机构建用的是 12:23 新生成的调试密钥（`6db37524`）——
    **两者不同，`adb install -r` 会被拒**（`INSTALL_FAILED_UPDATE_INCOMPATIBLE`，
    手机上什么都不会变）。要么找回旧机器的 `debug.keystore`，要么
    **先导出数据 → 卸载 → 装新版 → 导入**（详见 `docs/MIGRATION.md`）。
- ⚠️ **界面部分没有自动化验证**：编辑页与课表格子只能靠真机看，
  `dart analyze` 只保证编译得过，保证不了布局不溢出、点击不报错。
- **步 6 为什么只改两处就够**（免得以后以为漏了）：
  `DataBundle` 同时是「导出/导入」和「局域网同步」的载体，
  而局域网两条方向的公共入口 `mergeIncomingBundle` 调的也是
  `DataBackup.applyMerge(bundle: …)` —— 所以只改 `DataBundle` + `applyMerge` 就覆盖全了，
  `lan_sync_client` / `lan_sync_server` 一行都不用动。
- **步 3 那个失败的复盘**（值得记住）：
  课表格子那一段我**凭印象编了一张节次表**（把第 12 节写成 19:40-20:30），
  真实是 19:40-**20:25**（第 13 节 20:30 开始），于是推出了一条错误的边界规则。
  修法是把规则改成「取距离最近的节边界、平局取靠前」，
  并**把测试数据换成从 `assets/calendar/*.json` 抄出来的真实 15 节**。
  教训：**凡是与校历数字有关的测试，数据必须来自校历文件，不能凭印象写。**
- **已修：课表从 13 行扩到 15 行**（2026-09-25 用户拍板）。
  原来 `schedule_view.dart` 写死 13 行、`sessionTime` 却有 15 节，
  于是第 14、15 节（21:20 之后）的**课程与自定义日程都画不出来**。
  现在两边共用一个常量（`ScheduleView._rowCount` / `TimetableRowLayout.rowCount`），
  左侧时间表补齐第 14、15 节（21:20 / 22:10），网格高度下限从 380 提到 460
  （15 行按 380 分只有 25px/行，字会挤到看不清）。
  ⚠️ 这是**排版改动，需要真机看**：行更矮了，课程卡片与日程卡片都变小。
- **已修的另一个真 bug（2026-09-25，静态复查发现）**：课表与日历那两处取数
  用的是**全量** `userEvents`，于是**下学期建的例会会出现在本学期那张表上**
  （位置还按本学期的节次算，而且没有对应课表可对照）。
  修法：两处都改成只铺**属于该学期**的日程（外加没写学期的那种"不限学期"）。
  回归测试见 `test/user_event_semester_filter_test.dart`。
- **写文档时发现并补上的漏**：`pruneUserEventTombstones`（墓碑 180 天清理）
  写了却**没有任何地方调用** → 墓碑会随删除次数无限增长。
  已接在 `CalendarController.loadUserEvents()` 里（幂等、代价很小）。
- **已修的第三个真缺口（2026-09-25 静态复查发现）**：**点日程卡片什么都不会发生**。
  `createCard` 的 tap 只在 `deadlineList` 里按 `fromUid` 找待办，而自定义日程不在待办里
  → 点下去没有任何反应，卡片上那个打钩圆圈同理也不显示。
  现在接通了：**点卡片 → 编辑页（标题栏右侧有删除入口）→ 保存或删除 → 日程页刷新**。
  退出契约从 `UserEvent?` 换成了 `UserEventEditResult`（`saved` / `deleted`），
  好让"取消"与"删除"分得清。
- **入口自检**（免得再出现"写了函数没人调"）：`+` → `newUserEvent` ✓、
  卡片 → `_editUserEventCard` ✓、`saveUserEvent` / `deleteUserEvent` /
  `replaceUserEvents` / `pruneUserEventTombstones` 各自都有调用点 ✓。
- **已修的第四个真缺口（2026-09-25，真机反馈之外、静态复查发现）**：
  **编辑页的颜色选择器压根不影响任何显示**。`UserEventPalette.resolve()`
  在整个 lib/ 里没有调用者，`event.color` 只写进 Hive 和草稿 —— 用户导出里
  能看到他选了 `0xFF66CCFF`（天依蓝），但月视图/当天列表走的是
  `UidColors.colorFromUid()` 的散列色。现在月视图小圆点、当天列表色块、
  「接下来」的配色都认这个颜色（课表**仍固定粉**，SPEC.md R3 的要求，不能动）。
  由**待办**产生的日程时段维持散列色：那不是本次的新实体，不该顺手换色。
  教训与上一条一模一样：**字段存下来了不等于有人用它**，
  所以这轮起把"这个字段谁在读"也纳入入口自检。

### 验证记录

| 时间 | 验证者 | 结果 |
| --- | --- | --- |
| 2026-09-25 | 用户终端 `flutter test`（全量，步 1-3 数据层） | ✅ **742 个用例全过** |
| 2026-09-25 | 用户终端 `flutter test`（全量，步 3 接线 + 步 4） | ✅ **816 个用例全过**（其中一次 `-1` 是测试自己把区间端点写错，代码没问题） |
| 2026-09-25 | 用户终端 `flutter test`（全量，步 7 + 四处修复之前） | ✅ **861 个用例全过** |
| 2026-09-25 | **我跑了全量 `flutter test`**（四处修复 + 颜色接线之后） | ✅ **871 个用例全过**（`All tests passed!`，新增 10 个用例：`anchorDateFor` 6 个 + `buildUpcoming` 的 eventColors 4 个） |
| 2026-09-25 | 我（每次提交前必跑） | `dart analyze --no-fatal-warnings` → **0 error**；21 warning + 155 info，全部落在本次功能之外的既有代码里（唯一一处在我改过的文件里的 `calendar_view.dart:60` 那个多余 cast，已经用分支起点那一版核对过：功能之前就有） |

> **更正（2026-09-25）**：这份清单早先写着"我在沙箱里跑不了 `flutter test`，
> 所以每一步都需要用户跑一次全量测试"。**这句是错的**：`flutter test` 在
> 放宽沙箱（`danger-full-access`，会弹一次授权框）之后能正常跑完，
> 871 个用例就是我自己跑出来的。真正跑不了的只是**在受限沙箱里**跑。
> 以后同类工作可以先申请一次放宽，由我自己跑全量，不必每次都占用你的时间；
> 但**真机上的界面行为仍然只有你能验**（见 `tools/manual_check_user_event.md`）。

除了全量测试，我平时能自己跑的还有：`dart analyze`，以及**纯逻辑部分**的临时验证程序
（把纯 Dart 文件复制到临时目录、import 改相对路径后跑断言，**不进仓库**）。
这个手段已经抓到一个真 bug（见下面「已抓到的真 bug」）。

### 拆解（每步一个分支，做完一步给一次 analyze + test 原始结果）

| 步 | 分支 | 内容 | 状态 |
| --- | --- | --- | --- |
| 1 | `feat/user-event-model` | `UserEvent` 模型 + 发生规则纯函数（自然周几 + 间隔 + 截止日） | ✅ 已提交 `0000b57` |
| 2 | `feat/user-event-store` | 独立 box + 墓碑 + store（照 `course_mount_store.dart`，不新增 typeId） | ✅ 已提交 `976cf19` |
| 3 | `feat/user-event-calendar` | 展开成 `Period`、接进月视图当天列表与「接下来」 | ✅ 已提交 `7ddb444`（数据层）+ `28be44b`（接线） |
| 4 | `feat/user-event-edit-page` | 新建/编辑页 + `+` 弹选择 | ✅ 已提交 `9c9bd80`（数据层）+ `bf5aafc`（界面） |
| 5 | `feat/user-event-timetable` | 接进课表格子（两种时间口径、冲突叠加、**粉色**） | ✅ 已提交 `7f76ec0`，并已 `merge` 回主线分支 `f41a7d3`（**当时漏并过一次，见下面的流程教训**）|
| 6 | `feat/user-event-sync` | 导出/导入/局域网同步/合并四处一起改 | ✅ 已提交 `8da5017` |
| 7 | `docs/user-event-docs` | 更新 `MULTI_DEVICE_SYNC.md` 与 `FEATURES.md` 相关段落 | ✅ 已提交 `f916681`（`FEATURES.md` 七之二 + 同步一节）|
| 收尾 | `feat/user-event-edit-page` | 真机反馈的 4 处问题 + 颜色接线 | ✅ 已提交 `b3b74f3` / `e901c94`，**待你在真机上复验** |

### 步 1、2、3 的实际产出

| 文件 | 作用 |
| --- | --- |
| `lib/mod/user_event.dart` | 模型（字段、自洽校验、toMap/fromMap、copyWith、说法文案） |
| `lib/mod/user_event_rule.dart` | 发生判定（纯逻辑）：occursOn / occurrencesBetween / nextOccurrence |
| `lib/mod/user_event_date.dart` | 三行的日期助手（见下「为什么多开一个文件」） |
| `lib/mod/user_event_merge.dart` | 合并口径（纯逻辑）：同 uid 比 updatedAt、墓碑优先、幂等 |
| `lib/mod/user_event_tombstone.dart` | 删除墓碑（uid -> 删除时刻）+ 同步包 wire 格式 + 过期清理 |
| `lib/mod/user_event_store.dart` | Hive/Get 接线：读写、保存即清墓碑、删除先留墓碑、同步包 |
| `lib/mod/user_event_periods.dart` | **日程 -> 可显示时段**：节次↔钟点换算、发生日展开、与课程冲突判定、到 `Period` 的薄转换 |
| `lib/database/database_helper.dart` | 加两个盒子 `userEventBox` / `userEventTombstoneBox`（**不新增 typeId**） |
| `lib/model/semester.dart` | 加一个**只读**访问器 `periodTimes`（节次→钟点换算表），让日程用与课程同一套口径 |
| `test/user_event_*.dart` 4 个 | 单测（判定 / 合并 / 墓碑 / 时段展开） |

### 步 3 的分层与「为什么计算层不碰 Period」

`UserEventCalendar` 只做计算，产出自己的轻量类型 `EventSpan`；
把它变成真 `Period` 是文件末尾两个**逻辑为零**的函数（字段一一对应）。

这么分是因为 **`Period` 会把 Flutter 拖进来**
（`period.dart` → `time_helper.dart` → `utils.dart` → `flutter_secure_storage`）：
一旦在计算里直接用 `Period`，"节次换算对不对、哪天该铺、像不像冲突"
这些最容易算错的东西就没法脱离 Flutter 环境验证了。
拆开之后，计算层可以整段拿去纯 Dart 跑（第 3 步 38 项断言就是这么验的）。

### 已抓到的真 bug（值得留着当教训）

**「只这一次」被当成了「每周」**：判定第 3 步原来写成
`if (!isSingleOccurrence) { 检查整周差 }`，于是 `repeatPeriod = 0` 时整段检查被跳过、
又没截止日拦着 → 9/14 建的日程，9/21 也判成发生。

**是靠跑起来发现的，不是读代码看出来的**。回归用例已补狠（下一周不发生、一年后也不发生、
扫一整年只应该有一天、负数间隔同样当只这一次）。

### 另一个坑（这次是验证程序自己的错，值得记）

验证程序里给"按节次"的构造助手写了个默认值 `endPeriod = 5`。于是传
`startPeriod: 6` 却不传 `endPeriod` 时，得到"第 6 节开始、第 5 节结束"——
开始晚于结束，被 `spanOf` 按「单时刻」折成零长度，冲突判定于是永远不成立。
表面看像判定写错了，实际是测试夹具的默认值坑人。

两条教训都写进了代码注释与单测助手的注释里。

### 流程教训（这次错在我，不在代码）

**第 5 步提交在了另一个分支上，忘了并回来。** 第 5 步（课表扩到 15 行）写在
`feat/user-event-timetable`，之后我 `git checkout` 回 `feat/user-event-edit-page`
继续做第 6、7 步，**没有把第 5 步 merge 回来**。你在那个分支上 `flutter run`，
于是拿到的构建仍然是 13 行、粉色卡片不出现 —— 你报的第 4 条有一半是这么来的。

后果比"少一个功能"更糟：那个分支上的 `test/calendar_bundled_test.dart` 引用了
只存在于另一分支的 `user_event_timetable.dart`，也就是说**这个分支当时根本编译不过**
（`dart analyze` 会直接报 `uri_does_not_exist`）。我当时没发现，因为那几次 analyze
是在**另一个**分支的工作区里跑的。

修法：一个 `merge --no-ff`（`f41a7d3`）并回来。**不用 rebase**：AGENTS.md 禁止历史重写。

以后的做法：**每步提交完立刻确认"我现在这个分支上，这一步的东西在不在"** ——
最省事的判据就是提交前跑一次全量 `flutter test`（现在我能自己跑了），
编译不过或引用了不存在的东西会当场暴露。

### 我在清单里写错了列，害用户白测一轮（2026-09-25）

`tools/manual_check_user_event.md` 第 ③ 步原来写「在**周一**那一列找粉色卡片」，
可清单第 ① 步让用户填的「第一次发生在」预填的是**今天**（2026-09-25 = **周五**），
于是卡片画在**周五**那一列。用户照我写的去找周一，什么都没有，报「课表仍然没有粉色卡片」。

而当时那个构建**是对的**。我后来用它允许的手段核实了：`adb` 截图 + 逐像素分析，
粉色块在 **y 1491..1782（第 11-13 行）、宽 119px**，颜色 `#FFB3D1`
= `#FFA6C9` 叠 85% 到白底上（正好是 `conflicts == false` 那一支）——
也就是卡片确实画出来了，在周五那一列。

同一个清单还有第二处同类错误：写着「如果有课应并排各占一半宽度」，
而 SPEC.md 的 D10 明写「**叠加显示 + 小角标**，不自动调整时间」。
并排只发生在**两条自定义日程**撞在一起时。两处都已改。

教训（与「凡是与校历数字有关的测试，数据必须来自校历文件」是同一条）：
**清单里凡是指位置/数字的话，必须由代码或数据算出来，不能凭印象写。**
我凭印象写了"周一"，代价是你白跑一轮。

顺带记一个能力，下次省事：**模型看不了图片，但能用 `adb` 截图 + 逐像素分析**
（本机 PowerShell + `System.Drawing`，把屏幕还原成色块文字图、按颜色分类统计）
来"看"手机屏幕，`adb shell input tap/swipe` 还能直接操作。这一轮就是这么定位的。
那些临时脚本与拉下来的 APK 都不进仓库。

### 为什么多开一个 `user_event_date.dart`

仓库里现成的 `dateOnly` 在 `lib/utils/utils.dart`，那个文件 import 了
`flutter_secure_storage`；一旦引进来，判定与合并就**没法脱离 Flutter 环境验证**了。
而这轮的 bug 正是靠"能脱离 Flutter 跑"抓到的，所以值得为它留一个三行的叶子文件。

（同时避免 `user_event.dart` 与 `user_event_rule.dart` 互相 import：
那样两个同名顶层函数会在同时 import 两者的文件里撞成 `ambiguous import`，实测过。）

### 本任务已核实的代码事实（免得下一个人重查）

- 课表是**周次规则**不是日期表：`Session` 只有「周几 + 第几节 + 单双周 + 上下半学期」，
  具体日期由 `Semester._buildPeriods()` 展开（`lib/model/semester.dart`）。
- `PeriodType.user`（日程）链路**已经全通**（月视图列表、形状、点开卡片、编辑、删除、
  「接下来」、iCal 导出都认它），但**产生它的唯一来源是待办**：
  `Task.getPeriodOfDay()` / `Task.deadlineOfTime()`。日程页右上角 `+` 建的是**待办**。
- 课表的颜色**不是蓝色**：`TimeColors.colorFromHour()` / `colorFromClass()`
  按小时/节次给红 → 琥珀 → 黄绿 → 绿 → 浅蓝 → 蓝紫 → 紫（`lib/design/custom_colors.dart`）。
  所以「自定义日程用粉色」必须**统一固定色**，否则会和 20 点后的紫、12 点前的红撞。
- 已用 Hive typeId 只有 **6**(Task) / **8**(Period) / **14**/**15**/**16** /
  **20**(FocusSession)。用户自造数据的先例是「独立 box + 值存 JSON，不新增 typeId」，
  例子 `CourseMount`（`lib/model/course_mount.dart` 有完整理由）。
- 同步与备份是**逐类手工列举**的（`data_backup.dart` + `lan_sync_client.dart`）。
  `courseMountBox` 当初就漏过一次，是后来补的 —— 新实体必须四处一起接。

---

# 二、已发现但没排期

| # | 事项 | 现状 / 该怎么看 |
| --- | --- | --- |
| I1 | `assets/sounds/` 只有占位文件 | 2026-09-25 加了 `.gitkeep`（提交 `9c85b73`）让目录存在，`pub get` / `build` / `test` 不再报 `unable to find directory entry`。**目录里没有任何音频**，桌面端提示音走「找不到文件」分支。要做桌面端时再二选一：补音频，或删掉 `pubspec.yaml` 第 88 行的声明并把 `desktop_notify.dart` 的候选路径改掉 |
| I2 | **`docs/DB_SCHEMA.md` 不存在** | AGENTS.md 第 5 条要求「改动涉及数据库 schema 时必须同步更新并说明迁移策略」，但仓库里从来没这个文件。要么补一份（box 名单 + typeId 占用 + 迁移口径），要么把 AGENTS.md 那条改写成实际口径。**在 #1 的步 2 之前要定**，否则新 box 没有地方登记 |
| I3 | `.gitignore` 第 411 行忽略 `pubspec.lock` | 上游既有约定（`v1.3.0` → 当前 HEAD 都没提交过它）。好处是不钉死版本、代价是换机器时依赖会重新解析。要改是独立决策，别顺手改 |
| I4 | 21 个 analyze warning（0 error） | CI 只对 error 敏感，当前不阻塞。里面有真东西：11 处 `unawaited_return_in_try_block`（`refresh_coordinator.dart`、`lan_sync_server.dart` 等）、`auto_relogin.dart` 的未用 import、`ai_compose_sheet.dart` 三个未引用元素、两处重复 import。**值得单独一轮清理**，别混进功能提交。另有 155 个 `info`（多是 `prefer_const_declarations` 一类），同样不阻塞 |
| I5 | git `safe.directory` 未配置 | 这台机器没有全局 `.gitconfig`，某些受限令牌下 git 会报 `dubious ownership`（`.git` 所有者是 `BUILTIN\Administrators`，和主流工程目录一致，**不是损坏**）。建议在你自己终端跑一次 `git config --global --add safe.directory 'D:/Personal Files/Neochron'` |

---

# 三、延后项（SPEC 明确推迟，不是忘了）

| # | 事项 | 推迟理由 / 该做时的条件 |
| --- | --- | --- |
| L1 | 自定义日程的**提醒**（SPEC D5） | 复用待办提醒管线会动去重与签名口径（`TaskReminder`），风险与本次目标不成比例。等 #1 落地、真机验证过「看得见」之后再单开一轮 |
| L2 | **「只删这一次」**（SPEC D7 的单次例外 `exdates`） | 要引入例外日期列表，会让展开与合并复杂一档。先在 #1 里做「整条删」，这一条单独立项 |
| L3 | 课表格子**点空白新建**（SPEC D8） | 两种时间口径下都要能反推节次/时刻，收益不如先把编辑页做扎实 |
| L4 | 自定义日程进**首页最近一条**（SPEC D9） | 先把「四处可见」做对，再谈首页聚合 |
| L5 | 与课程**冲突的自动处理**（SPEC D10 之外） | 自动挪时间是另一套产品决策，不在 #1 范围 |

---

# 四、已收口（最近）

| 事项 | 结论 | 证据 |
| --- | --- | --- |
| **应用改名：Elychron → Neochron**（2026-09-25，分支 `feat/rename-neochron`） | ✅ 完成。提交 `2dcd222`（测试小修）+ `cd75b35`（应用名 5 个文件）+ `ff5bd95`（界面文案 35 个文件）。验证：analyze 176（0 error / 21 warning，与改名前的基线一致）、全量 `flutter test` **+876 全过**、`aapt2 dump badging` 读出 `application-label:'Neochron'`（包名 `xyz.nosig.celechron.mod` 与 versionName 未变，签名仍是 `6db37524…`）。<br>**刻意不动的**（都不是漏）：`applicationId`/`namespace`/manifest `package`、Dart 包名 `celechron`、`accountName: 'Celechron'`（iOS 钥匙串里存着登录凭据）、`<data android:scheme="celechron"/>`（对外深链接）、Hive box 名与 `DataBundle.format='celechron-mod'`、导出前缀 `celechron-backup-*`、`fuse.dart` 的 `releaseRepo` 与校历上游地址、LICENSE/版权头、`CelechronLogLevel` 等内部类名。<br>系统日历名改成 `Neochron课表`，并把旧名 `Elychron课表` 加进 `legacyCalendarNames`（旧日历会被清理）。<br>**还没决定**：仓库自己的 `README.md` / `PRIVACY.md` 仍写 Elychron（那是项目说明与真实仓库地址，不算应用名）、GitHub 仓库名要不要一起改、`celechron://` 要不要再加一个 `neochron://`、`windows/linux/macos/ios` 四个模板工程里的名字（P2） | `git log --oneline feat/rename-neochron` |
| 环境搭建（Flutter / JDK / Android SDK / 开发者模式） | ✅ 全部就位，见 `tools/setup_env.md` 第六之二节 | Flutter 3.47.2 + Dart 3.13.2、JDK 21.0.12.1、build-tools 35/36、platforms 34/35/36 |
| 构建基线 | ✅ `flutter build apk --release` 成功 | `app-release.apk` 29,163,614 字节 |
| 静态检查基线 | ✅ **0 error**（22 warning + 155 info） | `dart analyze --no-fatal-warnings` |
| 测试基线 | ✅ **669 个用例全过** | 用户终端 `flutter test`（2026-09-25） |
| `assets/sounds/` 缺失导致 Flutter 报 Error | ✅ 加 `.gitkeep` | 提交 `9c85b73`；analyze 从 177 → 176 issues，`asset_directory_does_not_exist` 消失 |

---

## 与旧清单的关系（一句话）

旧清单是 **Elychron 到 v1.4.2 为止的历史记录**；本清单是 **Neochron 的实际工作入口**。
两边编号互不相干，引用旧条目时一律写明「出自旧清单 #NN」。
