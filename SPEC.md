# SPEC：日程自定义（在课表之上加自己的事）

> 状态：**待用户修改后确认**。本文件只是需求与方案，**代码一行都还没动**。
>
> 改造方向由用户 2026-09-25 提出：不改 BACKLOG 里的既有条目，转而改造「日程」功能，
> 在课表的基础上支持**自定义日程**（首个场景：学生组织例会）。
>
> 相关代码位置（本文件所有判断都来自实读，不是猜的）：
>
> | 关心的事 | 文件 |
> | --- | --- |
> | 日程页三个面（接下来 / 日历 / 课表）与当天列表 | `lib/page/calendar/calendar_view.dart` |
> | 日程页状态与取数、月视图标记 | `lib/page/calendar/calendar_controller.dart` |
> | 两周课表格子（只有课程/考试能进） | `lib/page/calendar/schedule_view.dart` |
> | 课程/考试 → 具体日期的 `Period` | `lib/model/semester.dart` 的 `_buildPeriods()` |
> | 日程卡片的数据形状 | `lib/model/period.dart`（`PeriodType.user`） |
> | 待办如何变成日程 | `lib/model/task.dart` 的 `getPeriodOfDay()` |
> | 本地库（box 名单、typeId） | `lib/database/database_helper.dart` |
> | 导出 / 局域网同步 | `lib/utils/data_backup.dart`、`lib/mod/lan_sync_client.dart` |

---

## 一、现在是什么样（我的实测结论）

先把事实摆清楚，方案才有落点。

1. **课表是「周次规则」，不是日期表。** 一条 `Session` 只有
   `dayOfWeek`（周几）、`time`（第几节到第几节）、`oddWeek` / `evenWeek`（单双周）、
   `firstHalf` / `secondHalf`（上下半学期）。**没有任何具体日期**。
   具体日期由 `Semester._buildPeriods()` 把「周次规则」展开到
   `Semester._dayOfWeekToDays`（由校历 `sessionTime` + 起止日算出来）上得到 `Period`。

2. **「日程」这一层已经存在，而且只由待办产生。** `PeriodType.user` 已经全链路打通：
   - 月视图当天列表、形状配色、点开卡片、编辑、删除都用它（`calendar_view.dart`）；
   - 「接下来」把它归为 `UpcomingKind.activity`（`upcoming.dart`）；
   - iCal 导出、`getCalendarStatistics` 也认它。
   - 但**产生它的唯一来源是待办**：`Task.getPeriodOfDay()`（`TaskType.fixed` 活动型）
     与 `Task.deadlineOfTime()`。日程页右上角 `+` 走的是 `newDeadline(...)`，建的是**待办**。

3. **用户今天已经能勉强做这件事**：建一条 `TaskType.fixed`（界面叫「活动」）的待办，
   设开始/结束时间 + `TaskRepeatType.weekday`（按周几重复）+ `repeatEndsTime`（重复到哪天），
   它就会出现在日历里。**但**：
   - 它活在**待办**的语义里 —— 出现在待办列表、有完成/逾期状态、会被
     `task_controller.dart` 在活动结束后自动归档成内部 `fixedlegacy`（界面叫《过去日程》）；
   - 复现不了「学期第 3-16 周、每两周一次」这种**学期周次**语义（只能按自然周几 + 截止日推）；
   - **进不了课表那面**（`schedule_view.dart` 只读 `semester.firstHalfTimetable` /
     `secondHalfTimetable`，那是 `Session` 的列表）；
   - 期末结束、下学期开始时它不会自动收口。

4. **`PeriodType.flow` 已经没用**（时间规划时代的遗留），`PeriodType.virtual` 只作占位。
   新东西不该借用它们。

5. **本地库的既有做法**（决定了本次不碰 schema）：
   - box 名单在 `database_helper.dart`，已用 Hive typeId 只有
     **6**(Task)、**8**(Period)、**14**/**15**/**16**(SubTask/Attachment/Comment)、**20**(FocusSession)；
   - 用户自造数据有先例走「**独立 box + 值存 Map/JSON，不新增 typeId、不注册 adapter**」，
     例子就是 `CourseMount`（键 = 课程代码，值 = Map，见 `lib/model/course_mount.dart` 的注释）。

6. **同步与备份的覆盖面决定了新数据的成本**：`data_backup.dart` 与
   `lan_sync_client.dart` 是**逐类手工列举**的（不只靠 `DataBundle`）。也就是说，
   **新加一种实体，必须同时改导出、导入、局域网同步、冲突合并**，否则数据只在单机上活着。
   参考 `courseMountBox` 的遭遇：它一开始「压根没进同步协议」，是后来补的。

---

## 二、需求（我理解的，请直接改这一段）

### 2.1 首要场景

> 我参加学生组织，**每周（或每两周）固定时间开例会**，地点固定或有时换。
> 我要它像课一样出现在课表里，而不是像一条待办那样躺在待办列表里等我打钩。

### 2.2 我理解的需求

- **R1** 能在日程页**新建自定义日程**，填写：标题、星期几、第几节（或具体时刻）、
  地点、备注、颜色/标签。
  
- **R2** 支持**重复**：只这一次 / 每周 / 每两周 / 每 N 周，配一个**截止日**。
  > **2026-09-25 用户拍板（见 D3）**：**不采用学期周次语义**（「第 3-16 周」那套），
  > 改成**按自然周几 + 截止日** —— 理由是**放假期间也可能有这类活动**，
  > 绑死学期周次会让假期里的例会用不了。代价是它不跟着校历的停课/调休走（见 D6）。
  
- **R3** 自定义日程要出现在**四处**：月视图当天列表、**课表那面**、「接下来」、当天列表。

  > 我希望它能出现在课表那面，但是要以不同的颜色标注。课表页面的课程以蓝色底色标注（这是已经有的），像这类的自定义日程以粉色标注。

  **落地口径（2026-09-25 核实后确定）**：
  - 课表的课程颜色**其实不是蓝色**：`TimeColors.colorFromHour()` / `colorFromClass()`
    按小时/节次给 **红 → 琥珀 → 黄绿 → 绿 → 浅蓝 → 蓝紫 → 紫**
    （`lib/design/custom_colors.dart`）。所以「用粉色区分」要成立，必须是
    **固定的粉色**，不能再用 `UidColors.colorFromUid()` 那套按 uid 散列的随机色；
  - 固定值取 **`#FFA6C9`（爱莉粉）**：仓库里已经有这个标准色
    （`MOD_NOTES.md` 的闹钟配色预设、`assets/logo.png` 同一色系），不引新色；
  - **必须避开时段色阶里的品红档**（`#C300FF`，≥20 点）与红档（≤8 点），
    否则「20 点的例会」和「8 点的课」会撞色，粉色的区分意义就没了。
    实现上：课表格子里**课程仍走时段色阶、自定义日程一律走固定粉**，两类不共用调色板。

- **R4** 能**点击编辑 / 删除**，删除要能整条删、也能只删某一次（待定，见 D7）。

- **R5** **跨学期收口**：上学期建的例会不该出现在下学期，除非我选了「一直重复」。

- **R6** 可选**提醒**（提前 N 分钟），与现有待办提醒共用一套投递管线。

- **R7** **与课冲突时看得见**（不能静默叠在一起让我漏掉）。

- **R8** 数据要能**导出 / 导入 / 局域网同步**，否则换手机就没了。

- **R9** **不破坏**现有课表刷新链路：教务刷新、清缓存、合并旧数据都不能把自定义日程弄丢或重复。

### 2.3 明确不做（本 SPEC 范围内）

- 不做教务数据的任何写入（我们只读教务）。
- 不做「按日期一次性批量导入学期日程表」（等 R2 落地后另开）。
- 不碰 `applicationId`、不碰 `android/` 原生代码、不加任何依赖。
- 不改 `Session` / `Scholarship`（教务那侧）的存储结构。

---

## 三、方案

### 3.1 实体：新建 `UserEvent`，复用 `Period` 呈现

**决定的关键点：自定义日程不是待办。** 它没有「完成」，也就没有逾期、归档、
待办列表这些语义。硬塞进 `Task`（不论加 `TaskType` 还是加标志位）会把
「四种时间语义」这套地基搅浑，而且它会被自动归档逻辑带走。

因此新增一个模型，**只负责「一件事在哪些天、几点到几点」**：

```text
lib/model/user_event.dart        # 新：模型 + 展开成 Period 的纯函数
lib/mod/user_event_store.dart    # 新：读写 + 墓碑（照 course_mount_store.dart 的做法）
lib/mod/user_event_rule.dart     # 新：发生判定（纯逻辑，配单测）
lib/page/calendar/user_event_edit_page.dart   # 新：新建/编辑页
```

字段（草案，字段名与含义请直接改）：

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `uid` | String | 主键，uuid v4 |
| `title` | String | 标题，如「学生会例会」 |
| `startDate` | DateTime | 第一次发生的日期（只取日期部分）。**它同时是「每两周」的奇偶基准**，见 3.3 |
| `dayOfWeek` | int | 1=周一 … 7=周日（与 `Session.dayOfWeek` 一致）。**必须与 `startDate` 对得上**，写入时校验 |
| `startPeriod` / `endPeriod` | int? | 第几节到第几节（与 `Session.time` 同一套编号，1..13）。与下面一对**二选一** |
| `startClock` / `endClock` | String? | `"19:00"` / `"20:30"` 这种具体时刻。与上面一对**二选一**（见 D4） |
| `repeatPeriod` | int | 间隔**周数**：1 = 每周、2 = 每两周、3 = 每三周…… 与 `Task.repeatPeriod` 的命名保持一致（那边单位是天，这里是周） |
| `repeatUntil` | DateTime? | 重复到哪一天为止。**null = 一直重复**（不设默认终点；放假也要能用，见 R2/D3） |
| `semesterName` | String? | 归属学期（`Semester.name`，如 `2026-2027-1春夏`）。**只用于在课表面挑「看哪个学期」**，不参与发生判定；null = 不限 |
| `location` | String | 地点 |
| `note` | String | 备注 |
| `color` | int? | 用户选的颜色；null = **固定粉 `#FFA6C9`**（见 R3 的落地口径，不再用 `UidColors` 散列色） |
| `reminderEnabled` | bool | 是否提醒（第一期不做投递，见 D5，但字段先留着，避免以后加字段动协议） |
| `reminderLeadMinutes` | int? | 提前量；null = 沿用设置的默认值 |
| `createdAt` / `updatedAt` | DateTime | 同步与合并要用 |

> **`half` 字段已删除**：原来是为「学期周次」口径准备的（判断落在上半还是下半学期）。
> D3 改成自然周几 + 截止日后，**发生判定不再需要学期周次**，这个字段没有意义了。
> 但**课表面**仍要知道「这条属于哪个学期」才能决定画在哪张表上 —— 那用 `semesterName`，
> 不用周次推算（这也是它保留的原因）。

**展开成 `Period`**：新增纯函数
`List<Period> userEventPeriods(UserEvent e, Semester semester)`，
用与 `Semester._buildPeriods()` **同一套**日期口径把它摊到具体日期上，
产出 `PeriodType.user` 的 `Period`，其中：

- `fromUid = e.uid`（点卡片时据此找回原对象，与 `Task` 的做法一致）；
- `uid = '${e.uid}-${yyyyMMdd}'`（某一次的唯一键，用于去重与「只删这一次」）；
- `summary = e.title`、`location`、`description = e.note`。

> **为什么用纯函数而不是塞进 `Semester.periods`**：`Semester` 是**教务数据的容器**，
> 每次刷新都会重建/合并它。把用户数据混进去，刷新时一合并就可能是重复或丢失。
> 数据各待各的容器，只在**渲染时**合并 —— 这也是 `calendar_controller` 现在对
> 待办做的事（`getEventsForDay()` 里把 `taskList` 的 Period 拼进来）。

### 3.2 存储：独立 box + JSON 值，不新增 typeId

照 `CourseMount` 的先例：

```text
box:  dbUserEvent          （键 = uid，值 = 一份 Map/JSON）
box:  dbUserEventTombstone （键 = uid，值 = 删除时间；跨设备删除要它）
```

- **不新增 `@HiveType` / 不注册 adapter** → 零 schema 风险、零迁移脚本，
  以后加字段不用动 Hive 编号（AGENTS.md 第 5 条的初衷正是这个）。
- 需要在 `database_helper.dart` 里加两处：`late final Box userEventBox;` 与
  开 box 的那一行；再加两条 `final String dbUserEvent = 'dbUserEvent';`。
- **读不动的脏数据整条丢掉**，绝不让日程页崩（照 `CourseMount.fromMap` 的做法）。
- 墓碑口径照 `lib/model/tombstone.dart` 与 `lib/mod/course_mount_tombstone.dart`：
  删除先留墓碑，避免另一台设备把已删的日程推回来。

### 3.3 发生判定（纯逻辑，必须有单测）

> **口径已按 D3 改为「自然周几 + 间隔周数 + 截止日」**，
> 原来的「学期周次 / 单双周 / 上下半学期」那套**不再使用**。

`lib/mod/user_event_rule.dart` 只做一件事：**某个日期算不算发生**。

```text
给定 UserEvent，判断 date 这一天是否发生：
  1. 星期几：date.weekday == e.dayOfWeek ？（不等直接 false）
  2. 起点：date 不早于 dateOnly(e.startDate) ？（早于直接 false）
  3. 间隔：相隔周数 = date.difference(e.startDate).inDays ~/ 7
           必须能被 e.repeatPeriod 整除（repeatPeriod = 1 时恒成立）
  4. 终点：e.repeatUntil == null，或 date 不晚于 dateOnly(e.repeatUntil)
  5. 全部通过 → 发生；否则不发生
```

**为什么要 `startDate` 而不是「只按周几 + 每两周」**：
「每两周」必须有一个**奇偶基准**，否则无法判断「这周是开例会的那一周吗」。
`startDate` 就是这个基准 —— 它同时承担「从哪天开始」的语义，一个字段两用，不额外加字段。

**易错点（要在注释里写明，别让下一个人踩）**：

- **第 3 步必须用整周差**（`inDays ~/ 7`），不能直接拿天数取模：
  跨夏令时/时区跳变时 `inDays` 会差 1，用整周差并对 `startDate` 取日期部分最稳。
- **`dayOfWeek` 与 `startDate` 必须自洽**：编辑页要**校验并自动纠正**
  （用户改了开始日期就顺手把周几改成那天的周几），否则会出现「这条日程永远不发生」的
  静默故障。测试要钉住这个校验。
- **`repeatUntil` 为 null 时没有终点**：这意味着它会一直重复到用户手动停。
  这是 D3「放假也能用」的直接后果 —— **不要**偷偷给它加「到学期末」的默认值，
  那等于把已经拍板的口径又改回去了。
- **校历的假期 `holidays` 与调休 `exchanges`**（`semester.dart` 第 326-343 行，
  课程会在那两步被搬走/砍掉）：**本功能都不参与**（见 D6 的结论），
  但**要在代码注释里写明为什么不参与**，否则下一个人会以为是漏了。
  注意这里与 D6 的原始表述（「调休跟着走」）有出入：**D3 改成自然周几之后，
  调休无从「跟着走」**（不再有学期周次的概念，也就没有可搬的目标日）。
  所以最终口径是：**假期与调休都不影响自定义日程**；真需要挪某一次，
  现阶段的办法是删掉重建（「只删这一次」见 L2/旧决策 D7）。

### 3.4 课表那面：两块内容拼一屏

`schedule_view.dart` 现在的格子只画 `Session`（`_buildCourseScheduleByDayOfWeek`）。
改法：

1. 取到「属于本学期的自定义日程」，用 3.3 的规则算出**本周那 7 天**的 `Period`。
   注意课表那面是**两周表格**（上/下半学期各一张，每张内按周几分列），
   所以是「上/下半学期 × 周几」两套 —— 但**判定本身与学期周次无关**（D3），
   这里只是决定「画在哪张表上」，用 `semesterName` 归属即可；
2. 与课程卡片**同一层 `Stack` 里定位**：
   - **按节次**的自定义日程：直接复用现有的 `(period.item1 - 1) * height / 13` 定位，
     与课程完全同一套坐标；
   - **按时刻**的（D4 选了才可能）：按 `sessionToTime` 反查落在第几节，跨节就跨行。
3. 视觉上必须和课程**一眼区分**（见 R3 的落地口径）：
   **课程仍走 `TimeColors.colorFromHour` / `colorFromClass` 的时段色阶**，
   **自定义日程一律用固定粉 `#FFA6C9`**，两类不共用调色板；
   再加一个形状标识来源（`periodTypeShape[PeriodType.user]` 已经是箭头形）。

### 3.5 日程页：新建 / 编辑入口

- **日历面右上角 `+`** 现在是直接建待办。改成**先问一句「新建待办还是新建日程」**
  （`showCupertinoModalPopup`，与现有 `newDeadline` 同一风格），或换成两个图标。
  选哪个 = D2。
- **课表面**：点空白格子新建（可选，成本较高）→ D8。至少先做「点自己的日程卡片 → 打开编辑页」。
- 编辑页字段与 3.1 的字段一一对应，风格照 `lib/page/task/task_create_page.dart`。

### 3.6 提醒

- 复用现有的 `TaskReminder` / `task_alarm_center` / `scheduleSystemAlarm` 那条管线会**牵动待办的签名与去重口径**，风险不小。
- 建议**第一期只做「在日程页/课表上看得见」**，提醒留到第二期，用
  `flutter_local_notifications` 的 `zonedSchedule` 直接对「下一次发生时刻」排一条。
- D5 请你拍板。

### 3.7 同步与导出（不能漏，否则数据只在单机上）

要**同时**改这四处，并各配一条测试：

| 位置 | 要加什么 |
| --- | --- |
| `lib/utils/data_sync.dart` | `DataBundle` 加 `userEvents` / `userEventTombstones`；`DataMerge` 加合并规则（同 `uid` 比 `updatedAt`；墓碑优先；合并幂等） |
| `lib/utils/data_backup.dart` | 导出、导入时读写这两个 box；导入前照旧先写 `before-import.json` |
| `lib/mod/lan_sync_client.dart` | 打包/解包（`courseMountBox` 就是加在这里的，照着抄） |
| `docs/MULTI_DEVICE_SYNC.md` | 协议文档里补一段字段说明 |

**格式标识不要动**：`data_sync.dart` 里的 `format = 'celechron-mod'` 改了会让用户已有备份与旧客户端同步包全部被拒（`docs/RELEASE.md` 有记录）。

### 3.8 测试计划（先写测试，再加功能）

| 测试文件 | 覆盖什么 |
| --- | --- |
| `test/user_event_rule_test.dart` | 发生判定：只这一次 / 每周 / 每两周（奇偶基准取自 `startDate`）/ 每 N 周；`startDate` 之前不发生；`repeatUntil` 为 null 时无终点、非 null 时含端点；`dayOfWeek` 与 `startDate` 不自洽时被校验拦下；**假期与调休都不影响判定**（钉住 D6 的最终口径） |
| `test/user_event_period_test.dart` | 展开成 Period：某次课的 uid 稳定（同一天两次调用一致）、时间正确、`fromUid` 指回原对象 |
| `test/user_event_sync_test.dart` | 合并：新增 / 更新较新者胜 / 墓碑阻止复活 / 幂等 / 老备份（没有该字段）仍能导入 |
| `test/user_event_store_test.dart` | 脏数据整条丢弃不崩；墓碑读写；删除后不再出现在展开结果里 |
| `test/version_consistency_test.dart`（既有） | 不动它，但提醒：改 `pubspec.yaml` 版本时要同步 `fuse.dart` |

`flutter analyze` 必须 **0 error**；`flutter test` 必须全绿（当前基线 669 个用例全过）。

---

## 四、我提请你拍板的地方（每题都有我的倾向）

| # | 问题 | 我的倾向 | 理由 | 我的意见 |
| --- | --- | --- | --- | --- |
| **D1** | 自定义日程做成**新实体**，还是给 `Task` 加一个 `TaskType`？ | **新实体** | 日程没有「完成」语义；塞进 Task 会被待办列表、归档、完成逻辑一起带走。新实体更干净，但同步/导出要手工接四处（3.7 已列） | 按你的来 |
| **D2** | 新建入口放哪？`+` 弹选择，还是课表/日历各放一个入口？ | **`+` 弹选择（待办 / 日程）** | 改动最小，且两种都能建；以后觉得烦再拆成两个图标 | 按你的来 |
| **D3** | 重复怎么表达？**学期周次**（第 3-16 周、每两周）还是**自然周几 + 截止日**？ | ~~学期周次~~（原倾向） | 你的场景（学生组织例会）天然是按学期排的；老师停课/放假时也能跟着校历走 | ✅ **用户定为「自然周几 + 截止日」**：放假也可能有这类活动。**已按此改掉 3.1 字段表与 3.3 判定** |
| **D4** | 时间按**节次**（第 5-6 节）还是**具体时刻**（19:00-20:30）？ | **两个都支持，节次为默认** | 例会通常按钟点（19:00），课表却按节次排版；两个都支持才能在课表格子里对齐。只做节次会限制真实用法 | 按你的来 |
| **D5** | 第一期做不做提醒？ | **不做，第二期** | 复用待办提醒管线会动去重与签名口径，风险与本次目标不成比例 | 按你的来 |
| **D6** | 校历里的**假期 / 调休**要不要作用于自定义日程？ | ~~假期不动、调休跟着走~~（原倾向，**在 D3 改动后已不成立**） | 例会在放假那天本来就不开（不该自动消失），但调休上班日应该跟着挪 | 你说「按你的来」，但这条的倾向随 D3 失效了 —— **请复核下面的「D3 的连带影响」第 1 条**。最终口径暂定：**假期与调休都不影响自定义日程** |
| **D7** | 删除粒度：整条删，还是能「只删这一次」？ | **先只做整条删**，单次例外（`exdates`）列 BACKLOG | 「只删这一次」要引入例外日期列表，会让合并与展开复杂一档，值得单独做 | 按你的来 |
| **D8** | 课表格子里点空白处新建，做不做？ | **先不做** | 点空白需要在两种时间口径下都能反推节次/时刻，收益不如先把编辑页做扎实 | 按你的来 |
| **D9** | 自定义日程要不要出现在**首页最近一条**、`home_mod_hooks` 那些地方？ | **第二期** | 先把「四处可见」做对，再谈首页聚合 | 按你的来 |
| **D10** | 冲突（与课程重叠）怎么显示？ | **在课表上叠加显示 + 卡片上加一个小角标**，不自动调整 | 自动挪时间是另一套产品决策，不在本次范围 | 按你的来 |

### D3 的连带影响（我按你的拍板改了方案，请你复核这三点）

D3 一改，有**三处**原来的表述跟着失效。我没有静默处理，全部摆在下面：

1. **D6 的「调休跟着走」落空了**（所以上表 D6 划掉了原倾向）。
   调休的本质是把某一天的课搬到另一天，而「自然周几」的日程**没有课程表这个概念**，
   也就没有可搬的目标日。**最终口径：假期与调休都不影响自定义日程**（已写进 3.3）。
   代价说清楚：中秋/国庆放假那天的例会不会自动消失，**要你自己删那几条或改截止日**。
   如果你不接受这个代价，那就得回到「学期周次」口径 —— 告诉我，我再翻回来。

2. **R5（跨学期收口）与 D3 冲突**：原来靠「学期周次」天然实现「上学期的例会不出现在下学期」，
   去掉学期周次后，一条没有终点的周例会**会永远重复下去**。建议的解法见下面新增的 D11。

3. **「校历单双周」这种排法变得不直接**：D3 之后它只能表达成
   「每两周 + 一个落在目标奇偶周的 `startDate`」，**不能**表达成「校历奇数周」。
   如果你的例会确实按校历单双周排，建的时候要挑对开始日期，并留意 3.3 的易错点第 2 条。

### 因 D3 新增的拍板项

| # | 问题 | 我的倾向 | 理由 | 我的意见 |
| --- | --- | --- | --- | --- |
| **D11**（新） | `repeatUntil` 默认填「本学期最后一天」，还是留空（一直重复）？ | **默认填本学期最后一天，且可清空** | 这样 R5 不用额外机制就成立；同时保留「放假也要用」的出口（清空即一直重复）。**发生判定本身不看学期**，学期只决定预填值与画在课表哪张表上 | 按你的来 |

---

## 五、实施顺序（确认后我按这个走，每步一个分支）

| 步 | 分支 | 内容 | 验证 |
| --- | --- | --- | --- |
| 1 | `feat/user-event-model` | `UserEvent` 模型 + `user_event_rule.dart`**发生判定**（自然周几 + 间隔周数 + 截止日，按 D3）+ 单测 | `flutter test test/user_event_rule_test.dart` |
| 2 | `feat/user-event-store` | 独立 box + 墓碑 + store（照 `course_mount_store`，不新增 typeId） | 单测 + 老数据不受影响 |
| 3 | `feat/user-event-calendar` | 展开成 Period、接进月视图当天列表与「接下来」 | 手测 + 单测 |
| 4 | `feat/user-event-edit-page` | 新建/编辑页 + `+` 弹选择 + **`dayOfWeek` 与 `startDate` 自洽校验** | 手测 |
| 5 | `feat/user-event-timetable` | 接进课表格子（两种时间口径、冲突叠加、**固定粉 `#FFA6C9`**） | 手测 + 真机截图 |
| 6 | `feat/user-event-sync` | 导出/导入/局域网同步/合并四处一起改 | `test/user_event_sync_test.dart`；老备份仍能导入 |
| 7 | `feat/user-event-reminder` | （**D5 第一期不做**，此步留到第二轮）提醒排程 | 真机 |
| 8 | `docs/user-event-docs` | 更新 `docs/MULTI_DEVICE_SYNC.md` 与 `FEATURES.md` 相关段落 | 文档与实现一致 |

> 每步做完我给你：改了哪些文件、怎么验证、`flutter analyze` 与 `flutter test` 的原始结果。

### 开工前还差一个回答

**D11**（`repeatUntil` 默认填学期最后一天还是留空）会直接决定第 1 步的字段初值和第 5 步的展示范围，
**请在你确认 SPEC 时一并给我答复**；不答复我就按「默认填学期最后一天、可清空」做。

---

## 六、风险与不做的事

| 风险 | 处理 |
| --- | --- |
| 与教务刷新抢数据 | 自定义日程**只在自己的 box 里**，`Scholar` 刷新一律不碰它（3.1 的理由） |
| 「第几周」两种口径搞混 | `user_event_rule.dart` 只用一个口径并在注释写明来源；测试钉住边界 |
| 同步漏一处导致「换机就没了」 | 3.7 四处一起改，`user_event_sync_test.dart` 钉住 |
| 课表格子挤压（13 行 × 6 列本来很紧） | 先叠加显示，不做自动重排；真机上截图确认不糊 |
| 老数据兼容 | 不新增 typeId、老备份里没这两个字段 → 照 `DataBundle` 现有「只加字段」契约走，`sync_bundle_test.dart` 已有先例 |
| Hive box 打不开 | 照 `openBoxResilient` 的既有做法（有锁与损坏的兜底），新 box 走同一个入口 |

**不做**：不写教务、不动 `applicationId`、不加依赖、不碰 `android/` 与 `ios/` 原生代码、
不改 `data_sync.dart` 的 `format` 字符串。
