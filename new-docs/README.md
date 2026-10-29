# new-docs 目录导航

本目录(`new-docs/`,位于仓库根目录下)是全部协作文档的正本,按**评估目的与文档类型**分为三个子目录:

| 子目录 | 收录内容 | 命名规范 |
|---|---|---|
| [`rules/`](./rules/) | 协作规则、决策记录等长期有效的约定性文档 | 主题命名(如 `github-collaboration-rules.md`) |
| [`evaluation/`](./evaluation/) | 评估报告、基准横评、能力测试报告等正式分析文档 | 主题命名 |
| [`records/`](./records/) | 一次性会话记录:分析笔记、测试记录、问题排查过程 | `YYYY-MM-DD-主题.md` |

## 文档索引

| 文档 | 位置 | 版本/日期 | 说明 |
|---|---|---|---|
| [GitHub 协作规则](./rules/github-collaboration-rules.md) | `rules/` | v1.4 / 2026-10-29 | 7 条协作规则、目录布局约定、仓库现状记录 |
| [MiniCPM-OCR 深度评估报告](./evaluation/MiniCPM-OCR-深度评估报告.md) | `evaluation/` | v1.1 / 2026-10-29 | 功能特点、OCR 能力、部署要求、二次开发四大方向评估,含双模型对比、竞品横评、商用许可、硬件成本与落地路线图 |

## 与其他目录的分工

- 仓库根目录即上游 MiniCPM-OCR 源码快照(`sdk/`、`docs/`、`assets/`、`scripts/` 等),只读使用,协作改动不进入上游目录;
- `workspace/`:协作用脚本与生成物(首次使用时创建,不与上游 `scripts/` 混用);
- 沙箱外层目录(`/home/z/my-project/` 下的 `skills/`、`upload/`、`download/`、`.env`)位于仓库之外,不入库;
- 新增文档时:先按上表选择子目录,再更新本索引,以 `docs:` 提交。
