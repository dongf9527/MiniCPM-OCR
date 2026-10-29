# GitHub 协作规则

| 项目 | 内容 |
|---|---|
| 版本 | v1.3 |
| 生效日期 | 2026-10-29 |
| 仓库根目录 | 沙箱根目录,当前为 `/home/z/my-project/`;以 `git rev-parse --show-toplevel` 实测为准(见规则 2) |
| 远程仓库 | `origin` → github.com/dongf9527/MiniCPM-OCR(分支 `main`) |
| 默认分支 | `main` |
| 适用范围 | 本仓库全部代码与文档改动,包括 AI 协作会话产生的所有变更 |
| 优先级 | 本规则高于会话临时约定;确需豁免时须在会话中明确说明并留档 |

---

## 1. 规则总览

| # | 规则 | 核心要求 |
|---|---|---|
| 1 | 唯一同步方式 | 所有代码/文档改动通过 git commit + git push 推送到 GitHub,不在对话中凭空产生代码 |
| 2 | 仓库位置 | 严格使用沙箱根目录作为仓库根目录(当前为 `/home/z/my-project/`,以 `git rev-parse --show-toplevel` 实测为准),不在其他目录创建 .git |
| 3 | 提交规范 | 小步提交,commit message 使用 conventional commits 风格(如 `feat:`、`fix:`、`docs:`) |
| 4 | 会话记录 | 分析/评估/测试记录写入 `docs/` 目录,以 Markdown 形式提交推送 |
| 5 | 禁止 force push | 绝不使用 `git push --force`;同理禁止对已推送 commit 执行 `--amend` 后再推送(等效 force,同样触犯本条);未推送 commit 的 amend 属修正笔误常规手段,不受限 |
| 6 | Rebase 前置 | rebase 前先评估替代方案(revert/merge),必要时提前告知确认 |
| 7 | bug 修复不重命名变量 | 修复 bug 时保持原变量名,仅在 refactor 时重命名 |

---

## 2. 规则详解

### 规则 1:唯一同步方式

所有代码/文档改动必须通过 `git commit` + `git push` 进入 GitHub 仓库历史,这是两个协作会话(或人机之间)之间**唯一可信的同步渠道**。对话内容会丢失、上下文会被压缩,git 历史才是事实来源(source of truth)。

落地要点:

- 对话中可以讨论方案、展示 diff、给出演示片段,但任何"定稿"的改动必须写进仓库文件再提交;
- 每个协作会话结束前确认两件事:工作区干净(`git status` 无未提交改动)、本地领先提交已推送(`git push` 完成);
- **反例**:只在聊天里贴了一段脚本"你先这样用"——下个会话它就失传了;
- **正例**:改动写入文件 → `git add` → `git commit` → `git push`,对话里只留简短说明与提交号。

### 规则 2:仓库位置

仓库根目录 = 沙箱根目录。当前沙箱环境中为 `/home/z/my-project/`;**一律以 `git rev-parse --show-toplevel` 的实测结果为准**——若沙箱环境迁移导致挂载路径变化,以实测值为准,并同步更新本文档与 `docs/README.md`。禁止在仓库根目录以外的任何路径执行 `git init`。目录职责如下:

| 路径 | 职责 | 是否入库 |
|---|---|---|
| `docs/` | 全部文档,按类型分子目录(见规则 4 与 `docs/README.md`) | ✅ 提交推送 |
| `scripts/` | 可复用的生成脚本、工具脚本 | ✅ 提交推送 |
| `download/` | 非文档类交付物(数据集、图片等)或用户明确要求放置的文件 | 按需 |
| `upload/` | 用户上传的素材原件 | 按需 |
| `skills/` | 环境内置技能,与本仓库无关 | ❌ 已 gitignore,禁止提交 |
| `MiniCPM-OCR/` | 上游项目源码快照(选项 B:纳入本仓库) | ✅ 提交推送,只读使用 |

注意:`MiniCPM-OCR/` 是上游 OpenBMB/MiniCPM-OCR 的**源码快照**(剥离上游 `.git` 后导入),只读使用,不在其中做协作改动;更新方式为整体替换后以 `chore:` 提交,并在 message 中注明新的上游 commit。协作产出(文档、脚本、报告)一律放在仓库根部的 `docs/`、`scripts/`、`download/`。

### 规则 3:提交规范

小步提交:**一个 commit 只做一件事**。修 bug 与重构分开(配合规则 7),文档新增与代码改动分开。commit message 采用 conventional commits 风格,格式:`<type>: <简短描述>`,必要时正文补充动机。

| type | 用途 | 示例 |
|---|---|---|
| `feat` | 新功能 | `feat: 新增 KIE 字段级评测脚本` |
| `fix` | 缺陷修复 | `fix: 修复跨页表合并时列数错位` |
| `docs` | 文档变更 | `docs: 新增 GitHub 协作规则` |
| `style` | 格式调整(不改逻辑) | `style: 统一脚本缩进为 4 空格` |
| `refactor` | 重构(不改行为) | `refactor: 抽取 OTSL 转换公共函数` |
| `perf` | 性能优化 | `perf: 页面切块改用并发调度` |
| `test` | 测试相关 | `test: 补充 latex_repair 边界用例` |
| `chore` | 构建/仓库事务 | `chore: 忽略本地环境文件并移出跟踪` |

- **反例**:`git commit -m "修改"`、`update`、一个提交里混着修 bug + 改格式 + 加文档;
- **正例**:`fix: 修复 Jev 阈值比较方向反了`(只含该修复)+ `docs: 补充阈值校准记录`(文档另起一笔);
- 提交前用 `git diff`(暂存前)与 `git diff --staged`(暂存后)自查,确认没有夹带无关改动。

### 规则 4:会话记录

分析、评估、测试类记录**必须写入 `docs/` 目录**,以 Markdown 形式提交推送,供后续会话与协作者查阅。`docs/` 按文档类型分子目录:

| 子目录 | 收录内容 | 命名规范 |
|---|---|---|
| `docs/rules/` | 协作规则、决策记录等长期约定性文档 | 主题命名(如本文档) |
| `docs/evaluation/` | 评估报告、基准横评、能力测试报告等正式分析文档 | 主题命名 |
| `docs/records/` | 一次性会话记录:分析笔记、测试记录、问题排查 | `YYYY-MM-DD-主题.md` |

- 内容要素:背景与目的、关键结论、支撑数据、遗留问题与后续待办;
- `docs/README.md` 是目录导航与文档索引,**新增文档须同步更新索引**;
- 与 `download/` 的分工:文档(含报告)一律以 `docs/` 为正本;`download/` 仅存放非文档类交付物或用户明确要求放置的文件;
- 若 `records/` 内某次记录沉淀为正式结论,升级为 `evaluation/` 或 `rules/` 下的主题文档;
- **反例**:测试跑完只说"结论是 X",没有落盘——换一个会话就要重测一遍。

### 规则 5:禁止 force push

- **禁止**:`git push --force`、`git push -f`、`git push --force-with-lease`;
- **禁止**:对**已推送**的 commit 执行 `--amend` 后再推送——这等效于改写远程历史,同样触犯本条;
- **允许**:对**尚未推送**的本地 commit 使用 `--amend` 修正笔误,这是常规手段,不受限;
- 已推送的提交发现错误时的正确处理:
  - 改错内容 → `git revert <sha>` 生成反向提交,历史保持只增不改;
  - commit message 写错 → 不改历史,在新 commit 的正文里说明勘误;
- 原因:任何改写历史的操作都会让其他克隆/其他会话的本地状态失效,冲突排查成本远大于多一个 revert 提交的成本。

### 规则 6:Rebase 前置

rebase 不是默认操作。执行前必须先评估两个替代方案:

1. **revert**:公开历史出错时优先选 revert(见规则 5),它不触碰既有提交;
2. **merge**:需要保留分支汇合轨迹、或 rebase 收益不明显时,merge 更安全。

仅当 rebase 带来明确收益(典型场景:整理**尚未推送**的本地提交序列)时才执行。凡涉及已推送分支或与他人共享的提交,必须**提前在会话中说明理由并获确认**后才能进行。rebase 完成后用 `git log --oneline --graph` 复核历史,再按正常流程 `git push`(不带 force)。

### 规则 7:bug 修复不重命名变量

修 bug 时**保持原变量名**,把 diff 压缩到只体现行为修复;重命名属于重构,只出现在 `refactor:` 提交里,且 fix 与 refactor **永不混入同一 commit**。

```diff
# ✅ 正确:fix 提交,diff 最小
- if score >= threshold:
+ if score > threshold:

# ❌ 错误:同一提交里既修逻辑又改名,真实修复被淹没
- if quality_score >= pass_threshold:
+ if ocr_score > review_threshold:
```

原因:最小 diff 让审查者一眼看到真实改动;`git blame` 保持干净,出问题时能精准定位引入提交;出事故可以只 revert 修复本身而不连带重命名噪音。

---

## 3. 仓库现状与遗留事项

- 2026-10-29 首次清理:发现 `.env`(含 `DATABASE_URL`)与上游克隆(嵌入仓库)曾被跟踪,已移出跟踪并加入 `.gitignore`(文件保留在磁盘);
- 2026-10-29 目录布局决策(选项 B):上游 MiniCPM-OCR 源码以快照形式纳入 `MiniCPM-OCR/` 目录(剥离上游 `.git`),快照基线为上游 commit `b33b474`;
- 2026-10-29 推送前历史重建:仓库最早的本地提交曾在索引中包含 `.env`,为避免敏感内容进入远程历史,在**全部提交均未推送**的状态下重建了干净历史(未推送状态下的合法整理,符合规则 5 与规则 6);
- 2026-10-29 远程闭环:配置 origin 并完成首次 push(`970c5e3...3260382` 共 5 笔提交),token 仅存于本地 `.git/config`;
- 2026-10-29 文档目录体系:建立 `docs/rules|evaluation|records` 分类结构,评估报告由 `download/` 迁入 `docs/evaluation/`,协作规则迁入 `docs/rules/`,新增 `docs/README.md` 索引;
- 2026-10-29 仓库根目录约定升级(v1.3):由硬编码绝对路径改为"沙箱根目录 + `git rev-parse --show-toplevel` 实测优先",适配沙箱环境迁移,并补充远程仓库信息;
- **待办**:首推使用的 GitHub token 建议吊销重发(曾在会话中明文出现),下次推送前更新 `.git/config` 中的凭证。

---

## 4. 常用命令速查

| 场景 | 命令 |
|---|---|
| 会话开工同步 | `git pull --ff-only && git status` |
| 确认仓库根目录 | `git rev-parse --show-toplevel` |
| 查看改动 | `git status` / `git diff` / `git diff --staged` |
| 提交 | `git add <file>` → `git commit -m "docs: ..."` |
| 推送 | `git push` |
| 修正未推送提交 | `git commit --amend`(仅限未推送) |
| 撤销已推送提交 | `git revert <sha>` |
| 复核历史 | `git log --oneline --graph -20` |

> 本文档自身即遵守上述规则:存放于 `docs/rules/`、以 Markdown 形式提交;后续修订一律走新的 `docs:` 提交,不改写历史。
