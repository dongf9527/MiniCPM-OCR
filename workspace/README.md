# workspace/

协作用脚本与生成物的统一存放目录(协作规则 v1.4,见 `../new-docs/rules/github-collaboration-rules.md`)。**不与上游 `scripts/` 混用**:上游目录是只读快照,本目录下的脚本可自由增改。

## 目录约定

| 路径 | 内容 | 是否入库 |
|---|---|---|
| `deploy-16g/` | 16G 显存单卡部署脚本包(llama.cpp GGUF 路径) | ✅ 提交推送 |
| `llama.cpp/` | llama.cpp 克隆与编译产物 | ❌ `.gitignore` |
| `gguf/` | 下载/转换得到的 GGUF 权重 | ❌ `.gitignore` |
| `jev-hf/` | Jev 原始权重与转换用目录 | ❌ `.gitignore` |
| `venv-*/` | 各独立虚拟环境(转换/SDK/渲染服务) | ❌ `.gitignore` |
| `run/` | 运行时 pid 与日志 | ❌ `.gitignore` |

大文件与虚拟环境不入库(见 `.gitignore`);所有**脚本**与**文档**入库。权重落盘后约 8 GB,请确保磁盘余量。

## 当前内容

- [`deploy-16g/`](./deploy-16g/README.md) — 面向 16 GB 显存 GPU 的 MiniCPM-OCR 1.0(+ Jev)部署脚本包。可行性依据见 `../new-docs/records/2026-10-29-16G显存跑OCR可行性评估.md`。
