# Neochron — Agent 工作说明

> **接手开发前先读 [`docs/HANDOFF.md`](docs/HANDOFF.md)**：
> 现状快照（包名/签名/仓库/测试基线）、代码地图、环境与工具的坑、
> 验证手段、以及"绝对不能改"清单与理由。这份说明只保留硬约束。

## 项目身份
- 基于 Celechron v1.3.0 (ceab2a4) → Elychron → Neochron 的三代衍生版
- 许可：GPLv3，整个仓库。不得引入 NonCommercial/专有依赖。
- 上游文件（banner.png、LICENSE、上游版权头）只读，不得删除或改写。

## 环境
- 构建路径必须是纯 ASCII：D:\neochron（junction → D:\Personal Files\Neochron）
- Flutter 版本：3.47.2 stable（Dart 3.13.2，装在 `D:\flutter`，revision 见 `.metadata`）
- 常用命令：
  - flutter pub get
  - flutter analyze
  - flutter test
  - flutter build apk --release --target-platform android-arm64 --no-tree-shake-icons

## 硬性约束（违反即拒绝执行）
1. 绝不执行 git push / force push / rebase 已推送分支 / 任何历史重写
2. 绝不提交 android/key.properties、*.jks、.env、任何 API Key 或学号密码
3. 绝不修改 LICENSE 或删除上游 copyright header
4. 绝不改动 applicationId 除非我明确要求
5. 改动涉及数据库 schema 时，必须同时更新 docs/DB_SCHEMA.md 并说明迁移策略
6. 不新增依赖，除非先在计划里说明理由与许可证结论并得到我确认

## 工作方式
- 非平凡任务（>2 个文件或涉及架构）：先给我一份书面计划（目标 / 要动的文件清单 / 风险 / 验证方式），等我确认再动手
- 一次只做一件事；做完给出：改了哪些文件、怎么验证、下一步建议
- 每个功能一个分支：feat/<kebab-name>
- 提交信息用 Conventional Commits（feat/fix/chore/docs/refactor/test）
- 提交前必须自己跑 flutter analyze 和 flutter test，把结果贴给我
- 不确定就问，不要猜着写。宁可停下来问，也不要编 API