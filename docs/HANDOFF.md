# Neochron 交接文档（给之后接手开发的 Agent）

> **写给谁**：下一个在这个仓库里干活的 Agent（人也可以看）。
> **怎么用**：先读这份，再读 [`AGENTS.md`](../AGENTS.md)（硬约束）与
> [`docs/BACKLOG.md`](BACKLOG.md)（待办与决策记录）。
> **时间基准**：2026-09-25（这一轮大改造的收尾日）。比这更新的状态以仓库为准。

---

## 0. 如果只记三件事

1. **这是第三代衍生版**：Celechron（官方，作者 `n0sig`/`nosig`）
   → Elychron（`Elyyyyyyyyxer`，昵称 Tixer）→ **Neochron（本项目）**。
   代码里仍到处是 `celechron` / `elychron` 字样，**多数是有意保留的**（见 §5），
   别当成漏改去"顺手修"。
2. **绝不 `git push`**（用户自己推，见 `AGENTS.md` 硬约束 1）；改动前跑
   `dart analyze` + `flutter test` 并把**原始输出**贴给用户（§7 有基线数字）。
3. **凡涉及数据/协议/命名的改动，先看 §5 的"绝对不能改"清单** —— 每一条都写了理由，
   以及改了会坏什么。

---

## 1. 现状快照（2026-09-25）

| 项目 | 值 |
| --- | --- |
| 应用名（桌面 / 标题） | **Neochron** |
| 安装包名 | `io.github.specialjudge.neochron`（2026-09-25 从 `xyz.nosig.celechron.mod` 换过来，见 §2.5） |
| Dart 包名 | `celechron`（`pubspec.yaml` 的 `name`，**有意不改**） |
| 版本 | `1.4.2-elychron.1+10`（versionCode **10**；后缀里的 elychron 待发版时改，BACKLOG I10） |
| 签名 | `D:\keys\neochron-release.jks`，别名 `neochron`，DN `CN=Neochron, O=Neochron, C=CN`，SHA-256 `1ecde30744d28360749269a24b3e87719fcde710ab5f283d12db9dbdf5deb31c`，v2 方案；**用户已备份 keystore 与密码各两处** |
| 仓库 | `https://github.com/SpecialJudge/Neochron`（public）；remote 名 **`mine`** |
| 其它 remote | `upstream` = 官方 `Celechron/Celechron`（跟版用）；`neochron` / `midstream` = 上一代 `Elyyyyyyyyxer/Elychron`（`neochron` 同时是 partial clone 的 promisor，见 §6.6） |
| 分支 | `main` = 集成分支，**与远端一致**；另有一批已合并的 `feat/*`、`chore/*`、`docs/*` 分支（可安全删除） |
| 测试基线 | `flutter test` → **+876 全过**；`dart analyze --no-fatal-warnings` → **176 issues / 0 error / 21 warning** |
| minSdk / targetSdk | 28 / 36（Flutter 3.47.2，JDK 21） |
| 构建路径 | 必须走纯 ASCII 的 `D:\neochron`（junction → `D:\Personal Files\Neochron`） |

---

## 2. 2026-09-25 这一轮做了什么（37 个提交）

### 2.1 自定义日程（BACKLOG #1，本项目的主功能）

需求与拍板全在 [`SPEC.md`](../SPEC.md)（R1-R9 需求、D1-D11 决策）。
实现分步提交：模型 `0000b57` → 存储 `976cf19` → 展开成时段 `7ddb444` →
接进日历/月视图/接下来 `28be44b` → 编辑页 `9c9bd80`+`bf5aafc` →
接进课表格子 + 课表扩到 15 行 `7f76ec0` → 导出/导入/局域网同步 `8da5017` →
点卡片编辑删除 `ba79c35` → 文档与验收清单 `f916681`。

真机反馈后又修了三轮：四处 UI/逻辑问题 `b3b74f3`、颜色选择器接线 `e901c94`、
真校历回归测试 `c2b50ed`。

**能力**（写文档时以此为准）：

- 日程页 `+` 里新建「日程」（与「待办」并列的独立实体，**不是** `Task`，见 SPEC D1）；
- 重复：只这一次 / 每周 / 每两周 / 每 N 周 + 截止日（D3 是**自然周几 + 截止日**，
  **不是**学期周次；放假也照常发生，不跟调休走，见 D6）；
- 时间：按节次 **或**按具体时刻（D4）；
- 出现在**四处**：日历当天列表、课表（粉色卡片）、「接下来」、当天列表（R3）；
- 与课程重叠：叠加显示 + 橙色角标，**不自动挪时间**（D10）；
- 颜色：4 套预设（默认爱莉粉 `#FFA6C9`）；月视图/当天列表/接下来跟随所选颜色，
  **课表一律固定粉**（R3 的口径：课程走时段色阶，共用调色板会撞色）；
- 参与导出 / 导入 / 局域网同步（含墓碑，删掉的不会同步回来）；
- 按 `semesterName` 归属学期（R5）。

**未做**（明确推迟，别当成 bug）：提醒投递（D5/L1）、只删某一次（D7/L2）、
课表点空白新建（D8）、进首页聚合（D9）、与课程的自动重排（D10 之外/L5）。

### 2.2 应用改名：Elychron → Neochron

42 个文件（应用名 5 个 + 界面文案 35 个 + 测试与文档）。提交 `cd75b35`（应用名）、
`ff5bd95`（文案）、`2dcd222`（测试小修）。
`aapt2 dump badging` 可验证：`application-label:'Neochron'`。

### 2.3 签名：从 debug 密钥换成本项目自己的正式密钥

- 背景：原先 `android/key.properties` 不存在 → `build.gradle` 退回 `signingConfigs.debug`，
  而 debug 密钥**每台机器不同**，换机器就没法覆盖升级；
  文档里记的那份 `D:\keys\elychron-release.jks` 是**上一代维护者的**，本项目从没拿到过。
- 现在：用户跑 `tools/setup_signing.ps1` 生成了 `D:\keys\neochron-release.jks`
  （脚本默认值已改成 Neochron，提交 `78394ab`）。
- **顺带修掉一个潜伏已久的坑**：该脚本是"无 BOM 的 UTF-8"，
  Windows PowerShell 5.1 会按 GBK 解码中文 → 一屏语法错误、**根本跑不起来**。
  已改成带 BOM 并把教训写进脚本头部（`600f6e3` / `7265b5f` / `017edad`）。
- 细节与指纹记录见 [`docs/RELEASE.md`](RELEASE.md) 的 P0-2 与「四、签名步骤」。

### 2.4 仓库迁到用户自己的 GitHub

remote `mine` = `SpecialJudge/Neochron`；`main` 已推。代码/文档里 7 处指向上一代仓库的
链接改成自己的（`fuse.dart` 的 `releaseRepo`、关于页源码链接、校历镜像候选④、
README 下载与 Issues、PRIVACY 的 API 与 Issues），提交 `50d601d`。
**故意保留** README 里指向 Elychron 的链接（那是出处声明）。

### 2.5 换成本项目自己的包名（BACKLOG I13）

起因是用户真机实测：装上一代 Elychron 时显示"更新"，随后报"已安装了较新版本"。
三条事实叠加：**包名相同**（都叫 `xyz.nosig.celechron.mod`）→ 系统当同一个应用；
叠加**签名不同**与**versionCode 更低**就成了"根本装不上"。

改动**只有一行**：`android/app/build.gradle` 的 `applicationId` →
`io.github.specialjudge.neochron`，提交 `c712b79`。

> ⚠️ **改 applicationId 时不要顺手改 `namespace`**：manifest 里的小组件与接收器用
> 相对名（`.MainActivity`、`.TodoWidgetReceiver`、`.ECardWidgetReceiver`），
> 按 `namespace` 解析；而 `namespace` 允许与 `applicationId` 不同。
> 另外代码里**没有硬编码包名**（5 处全是运行时 `packageName`），也没有 FileProvider
> authority 之类的声明 —— 这两点核实过，所以换包名才只需要一行。

**代价（已发生）**：换包名 = 换一个 App，手机上要搬一次数据
（导出 → 装新包 → 登录 → 导入；旧的包可以留着共存，确认没用再卸载）。

### 2.6 文档这一轮的更新

README 重写（`aa9cb3e`、`c21f85b`）、PRIVACY（局域网同步入口其实**是开着的**，
原先写的"未开放"是错的）、`docs/MIGRATION.md`（新增"从上一代搬过来"这条路）、
`docs/RELEASE.md`、`docs/UPSTREAM.md`、`docs/BACKLOG.md`、`MOD_NOTES.md`（顶部注明
"这是历史记录"）、`tools/setup_env.md`（环境与网络现状）。

---

## 3. 代码地图（先看这里，别从零翻）

### 3.1 自定义日程（新增的 23 个文件）

| 文件 | 干什么 |
| --- | --- |
| `lib/mod/user_event.dart` | 模型：字段、自洽校验、`toMap`/`fromMap`、`copyWith`、说法文案。**`dayOfWeek` 是派生字段，故意不进 `toMap`**（真源是 `startDate`） |
| `lib/mod/user_event_rule.dart` | 纯逻辑：`occursOn` / `occurrencesBetween` / `nextOccurrence`（自然周几 + 间隔 + 截止日） |
| `lib/mod/user_event_date.dart` | 三行日期助手。**单独成文件**是为了让规则层不 import `utils.dart`（那个会拖进 `flutter_secure_storage`） |
| `lib/mod/user_event_clock.dart` | `"19:00"` ⇄ `Duration` 的解析与格式化（同样是 Flutter-free 叶子文件） |
| `lib/mod/user_event_merge.dart` | 合并口径（纯逻辑）：同 uid 比 `updatedAt`、墓碑优先、幂等 |
| `lib/mod/user_event_tombstone.dart` | 删除墓碑 + wire 格式 + `prune(keepDays: 180)` |
| `lib/mod/user_event_store.dart` | Hive/Get 接线：`userEventBox` / `userEventTombstoneBox`（**不新增 typeId、不注册 adapter**，照 `CourseMount` 的先例） |
| `lib/mod/user_event_periods.dart` | `UserEventCalendar`：节次↔钟点换算、按天展开 `EventSpan`、与课程冲突判定、`toPeriod`/`toPeriods` |
| `lib/mod/user_event_timetable.dart` | `TimetableRowLayout`：一条时段占课表哪几行（`rowCount = 15`），**课表与日程共用一个行数常量** |
| `lib/mod/user_event_draft.dart` | 编辑页草稿 + 纯逻辑校验（有单测） |
| `lib/design/user_event_palette.dart` | 颜色预设（复用闹钟那 4 个主色，默认色就是 `UserEventCalendar.eventColorArgb`） |
| `lib/page/calendar/user_event_edit_page.dart` | 新建/编辑页 + 删除入口 |
| `lib/page/calendar/calendar_controller.dart` | 接线：`userEvents` 快照、`userEventCalendarFor`、`userEventSpansForWeekday`、`anchorDateFor`（**纯静态**）、`semesterContaining`（顶层纯函数） |
| `lib/page/calendar/schedule_view.dart` | 课表格子：`_rowCount = 15`、左列 15 个真实节次时间、日程卡片渲染 |
| `lib/utils/data_sync.dart` / `data_backup.dart` | `DataBundle` 里加了 `userEvents` / `userEventTombstones`（**`format` 仍是 `celechron-mod`，别改**） |

测试在 `test/user_event_*_test.dart`（规则、合并、墓碑、展开、草稿、调色板、
课表行、同步、学期过滤、**真校历真数据** `user_event_real_case_test.dart`）+
`test/semester_containing_test.dart` 里的 `anchorDateFor` 组 +
`test/calendar_bundled_test.dart` 里的 15 行护栏。

### 3.2 其它文档

| 文档 | 内容 |
| --- | --- |
| `SPEC.md` | 日程功能的需求与 D1-D11 决策（**改需求先改这里**） |
| `docs/BACKLOG.md` | 唯一的工作清单：进行中 / 已发现未排期（I1-I13）/ 延后项（L1-L5）/ 已收口 |
| `docs/BACKLOG-DEPRECATED.md` | 上一代（Elychron 时期）的清单，**不再使用**，只作历史 |
| `docs/FEATURES.md` | 功能说明（含 §七之二 自定义日程） |
| `docs/MULTI_DEVICE_SYNC.md` | 局域网同步与导出/导入 |
| `docs/RELEASE.md` | 发版清单 + 签名步骤（含本项目密钥指纹） |
| `docs/MIGRATION.md` | 数据迁移：从官方版 / 上一代 Elychron / 早期 Neochron |
| `docs/UPSTREAM.md` | 与上游的跟版流程与 GPL 合规要求 |
| `tools/manual_check_user_event.md` | 日程功能的真机验收清单（**⓪①②③ 已通过，④⑤⑥ 待做**） |
| `tools/setup_signing.ps1` | 生成密钥 + 写 `android/key.properties`（**必须带 UTF-8 BOM**） |
| `tools/check_env.ps1`、`tools/setup_env.md` | 环境自检与本机环境记录（**用户决定不入库**，未跟踪） |

---

## 4. 数据与协议：改一处必须改四处

新增一种实体（或给现有实体加字段）时，**必须同时覆盖**：

1. 导出（`lib/utils/data_backup.dart`）
2. 导入（同上，走 `replaceUserEvents` / `adoptUserEventTombstones`）
3. 局域网同步（`lan_sync_client.dart` / `lan_sync_server.dart` / `data_sync.dart` 的 `DataBundle`）
4. 冲突合并（`user_event_merge.dart` + 墓碑）

漏一处，数据就只活在单机上 —— `courseMountBox` 当年就是这么漏的（SPEC 第 6 条特意记着）。

导出文件的 wire 形状（用户那份导出实证过）：

```json
{ "format": "celechron-mod", "version": 2,
  "userEvents": [ { "uid": "evt-…", "title": "学生会例会", "startDate": 1790265600000,
                    "repeatPeriod": 1, "repeatUntil": 1798905600000,
                    "semesterName": "2026-2027秋冬", "color": 4284927231,
                    "startClock": "19:00", "endClock": "20:30", … } ],
  "userEventTombstones": { "evt-…": 1790322402749 } }
```

> 导出里**看不到 `dayOfWeek`** 是正常的（派生字段）；`null` 的 `repeatUntil` 表示"一直重复"。

---

## 5. 绝对不能改 / 有意保留的清单（逐条给理由）

| 东西 | 为什么别动 |
| --- | --- |
| `applicationId` | **2026-09-25 已按用户明确要求改成 `io.github.specialjudge.neochron`**；再改 = 换一个 App，用户得重搬数据。改它时**不要**动 `namespace`（见 §2.5 的警告） |
| `pubspec.yaml` 的 `name: celechron` | Dart 包名，221 个 dart 文件写 `package:celechron/...`；改它是独立的一次大改造 |
| `accountName: 'Celechron'`（`lib/utils/utils.dart`、`lib/database/database_helper.dart`） | **iOS 钥匙串的账户名**，里面存着登录凭据；改了会读不到已保存的账号 |
| `<data android:scheme="celechron"/>`（manifest） | 对外深链接。注意：与官方版/Elychron 共存时同名 scheme 会让系统弹选择框（BACKLOG I8 讨论过是否加 `neochron://`） |
| Hive box 名（`dbUserEvent` 等）与 `DataBundle.format = 'celechron-mod'` | 数据与备份的**兼容标识**；改了旧数据读不出、旧备份导不进 |
| 导出文件名前缀 `celechron-backup-*` | 用户 2026-09-25 明确决定保持不动 |
| `lib/worker/fuse.dart` 的 `releaseRepo` | **已指向本项目**（`SpecialJudge/Neochron`）。别再指回上游 —— 注释里写了三条理由（给上游导流 / 包名不同会装出第二个 App / 频繁请求别人服务器不合适） |
| `lib/http/calendar_config_parser.dart` 的地址列表 | ① 上游原站 HTTPS → ② 上游原站 HTTP → ③ 上一代搭的 Gitee 镜像 → ④ 本项目自己的 raw；**包里还内置一份**。都是有意的层级，别删也别乱排序 |
| `CelechronLogLevel`、`CelechronSliverTextHeader` 等**内部类名** | 不是用户可见文案，改它只会制造无意义 diff |
| `LICENSE`、上游版权头、README 里对 Celechron 与 Elychron 的**出处声明** | GPL 要求；且上一代改动确实在本仓库里，冒领不合适 |
| `docs/BACKLOG-DEPRECATED.md`、`docs/WHATS_NEW_*.md`、`MOD_NOTES.md` 的历史内容 | 历史记录，别"顺手更新"（`MOD_NOTES.md` 顶部已注明它是历史） |

---

## 6. 环境与工具的坑（这一节最省时间）

1. **构建路径必须纯 ASCII**：用 `D:\neochron`（junction 到 `D:\Personal Files\Neochron`），
   Gradle 在中文路径下会直接拒绝。
2. **本机只有 Windows PowerShell 5.1**（没有 `pwsh` 7）：
   - 不支持三元运算符 `? :`（那是 PS 7 的语法）；
   - 双引号字符串里的中文引号、反引号会破坏解析 —— 文本含反引号时用**单引号**字符串；
   - `.ps1` **必须保存为 UTF-8 带 BOM**，否则按系统 ANSI（GBK）解码 → 中文变乱码 →
     "数组索引表达式丢失"这类假语法错误（`tools/setup_signing.ps1` 就因此长期跑不起来）；
   - 写文件用 `[IO.File]::WriteAllText($p, $t, (New-Object Text.UTF8Encoding($false)))`；
     **别用** `Out-File -Encoding utf8`（PS 5.1 会写入 BOM）。
3. **提交信息写成文件** 再 `git commit -F`，文件放 `.git\COMMIT_MSG_TMP`，用完即删 ——
   这样能避开引号与编码的坑。
4. **沙箱**：`dart` / `flutter` / `git` / `adb` / `aapt2` / `apksigner` 都要放宽权限
   （`danger-full-access`，会弹一次授权）。**放宽之后 `flutter test` 是可以跑的**；
   受限模式下 Dart 起不了子进程，测不了。
5. **网络**：`github.com` 时通时不通（`push`/`fetch` 会报 `Connection was reset` /
   `Failed to connect`），而 `raw.githubusercontent.com` 与 `api.github.com` 基本可达。
   → 对照远端状态**用 API**，例如：
   `Invoke-RestMethod https://api.github.com/repos/SpecialJudge/Neochron/commits/main`。
6. **仓库是 `blob:none` 的 partial clone**：历史文件内容不在本地，`push` 时会去 promisor
   远端（上一代仓库）临时抓数据。网络好的时候跑一次 `git fetch --refetch neochron` 补齐。
7. **`core.autocrlf=true`**：工作区是 CRLF、仓库里是 LF。用编辑工具改多行文本时，
   若中途发生过 `checkout`/`merge`，可能报 "file changed since it was read" —— 重新读一次即可。
8. **`adb` 授权会掉**：`unauthorized` 表示要在手机上点"允许 USB 调试"；
   三星的「设置 → 安全与隐私 → 自动阻止程序(Auto Blocker)」会直接挡掉那个弹窗。
9. 临时验证脚本写在仓库内（如 `.tmp-verify\`）**用完删掉**，别留在工作区。

---

## 7. 验证手段（可复用）

| 目的 | 命令 | 基线 |
| --- | --- | --- |
| 静态检查 | `dart analyze --no-fatal-warnings` | 176 issues / **0 error** / 21 warning（**别让它涨**） |
| 单元与集成 | `flutter test` | **+876 全过** |
| 包名 / 标签 / 版本 | `aapt2 dump badging <apk>` | `package: name='io.github.specialjudge.neochron'`、`application-label:'Neochron'` |
| 签名 | `apksigner verify --print-certs <apk>` | `CN=Neochron`、SHA-256 `1ecde307…eb31c` |
| 手机上装的是哪一版 | `adb pull` 已装 APK 比 SHA-256；或查 `lib/arm64-v8a/libapp.so` 里的**独有字符串** | ⚠️ **APK 字节数不可靠**：改名前后都是 29,230,044 字节 |
| 看手机屏幕（模型可能没有图像能力） | `adb shell screencap -p /sdcard/s.png` → `adb pull` → 用 `System.Drawing` **逐像素分析**（按颜色分类、数行、定位元素） | 靠这招定位过"粉卡到底画出来了没有" |
| 操作手机 | `adb shell input tap/swipe` | **动用户手机之前先问**（用户曾明确同意过一轮） |
| 真机验收 | `tools/manual_check_user_event.md` | ⓪①②③ 已通过；④⑤⑥ 待做 |

---

## 8. 待办与决策（详见 `docs/BACKLOG.md`）

| 编号 | 状态 |
| --- | --- |
| I1 `assets/sounds/` 只有占位 | 未做（要做桌面端时再定） |
| I2 `docs/DB_SCHEMA.md` 不存在 | 未做（AGENTS.md 第 5 条要求它；`user_event` 没动 schema 所以暂不阻塞） |
| I3 `pubspec.lock` 被 gitignore | 上游约定，别顺手改 |
| I4 21 个 analyze warning | 未清理（值得单独一轮） |
| I5 `git safe.directory` 未配 | 未做 |
| I6 README/PRIVACY 的项目名 | ✅ 已改 |
| I7 GitHub 仓库名 | ✅ 已在 `SpecialJudge/Neochron`（旧链接失效属预期） |
| I8 `celechron://` 要不要加 `neochron://` | **未决**（共存时同名 scheme 会弹选择框） |
| I9 桌面端 / iOS 模板工程里的名字 | 未做（做桌面端时一起） |
| I10 版本号后缀仍是 `elychron` | 未做（下次发版顺手改，注意 versionCode 只能增） |
| I11 签名密钥 | ✅ 已换成自己的密钥并备份 |
| I12 迁到自己的仓库 | ✅ 已完成（`main` 已推） |
| I13 换包名 | ✅ 已完成（`io.github.specialjudge.neochron`） |
| L1-L5 | 日程提醒 / 只删某一次 / 假期调休 / 课表点空白新建 / 首页聚合 —— 都明确推迟 |

**用户侧还差一步**：手机上把旧包（`xyz.nosig.celechron.mod`）里的数据
导出 → 在新包（`io.github.specialjudge.neochron`）里登录 + 导入；
旧包确认没用后再卸载。

---

## 9. 下一步建议（按价值排序）

1. **发一版**：`pubspec.yaml` 改成 `1.5.0-neochron.1+11`（versionCode 只能增），
   重新构建，`git tag -a v1.5.0-neochron.1` 并推 tag，在 GitHub 上发 Release
   （把 APK、SHA-256、签名指纹写进说明 —— README 里已经这样承诺了）。
   清单见 `docs/RELEASE.md`。
2. **把真机验收补完**：`tools/manual_check_user_event.md` 的 ④⑤⑥。
3. **I8 / I9 / I10** 这三条小的收尾。
4. **L1（日程提醒）**：复用待办那套提醒投递管线会动去重与签名口径
   （`TaskReminder`），风险与收益要重新评估 —— 建议单开一轮、先写 SPEC。
5. 跟上游：`docs/UPSTREAM.md` 记着跟版流程；`upstream` remote 仍在。
