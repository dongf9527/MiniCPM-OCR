# deploy-16g — 16G 显存单卡部署脚本包

面向 **16 GB 显存 NVIDIA GPU、无并发需求** 的 MiniCPM-OCR 部署脚本包。推理路径为 **llama.cpp + GGUF**(官方低配推荐路径),可选叠加 **Jev 判别模型**(解析→评分→免检/复核门控)。

可行性依据与显存估算见 `../../new-docs/records/2026-10-29-16G显存跑OCR可行性评估.md`。

## 结论速览

| 项 | 标准路径(vLLM BF16) | 本包路径(llama.cpp GGUF) |
|---|---|---|
| 显存门槛 | ≥24 GB | **1.0 引擎约 4–6 GB;+Jev 共卡约 12–14 GB** |
| 驱动 | ≥580(CUDA 13) | ≥535 即可 |
| 编译 | vLLM feat-ocr 源码编译(20–40 min) | llama.cpp 常规 CMake 编译(数分钟) |
| DSpark 投机解码 | 支持 | 不支持(无并发场景影响有限) |
| 吞吐 | 高(1.2 pages/s @5090) | 低(单页秒级~分钟级,依硬件) |

## 显存预算(16G 卡,共卡方案,估算)

| 组件 | 常驻显存 | 说明 |
|---|---|---|
| 1.0 引擎(F16 GGUF,ctx 8192) | ≈4–6 GB | 权重 1.4 GB + mmproj 0.86 GB + KV cache |
| Jev 引擎(bf16 GGUF,ctx 16384) | ≈5–8 GB | 官方环境要求显存 ≥8 GB |
| 版面模型 PP-DocLayoutV3 | 0(默认 CPU) | `LAYOUT_DEVICE=cuda:0` 可切 GPU,+1–2 GB |

共卡且两引擎常驻时按 **12–14 GB** 预算,余量约 2–4 GB;若遇 OOM:先降 `JEV_CTX`(16384→8192),再降 `OCR_CTX`(8192→4096),版面模型保持 CPU。极端情况下两引擎不同时启动,按需起停(`90_stop_all.sh` 后单起其一)。

## 快速开始

前置:Ubuntu 22.04 类系统、NVIDIA 驱动 ≥535、磁盘 ≥15 GB、内存 ≥16 GB。全部命令在 `workspace/deploy-16g/` 下执行。

```bash
# 0) 体检:GPU/驱动/磁盘/工具链
bash 00_check_gpu.sh

# 1) 编译 llama.cpp(CUDA)
bash 10_build_llamacpp.sh

# 2) 下载权重:1.0 GGUF(2.3 GB)+ Jev 原始权重(约 4 GB)
bash 11_download_weights.sh

# 3) Jev 转 GGUF(官方无现成 GGUF,需本机转换,首次约 10–20 分钟)
bash 12_convert_jev_gguf.sh

# 4) 起 1.0 解析引擎
bash 20_start_ocr_engine.sh

# 5)(可选)叠加 Jev:转换环境 → 引擎 → 评分服务
bash 22_setup_jev_render_env.sh     # 装渲染环境(Chromium/Node/字体,较慢)
bash 21_start_jev_engine.sh
bash 23_start_jev_service.sh

# 6) SDK 环境(含版面模型依赖,版面默认走 CPU,不占显存)
bash 30_setup_sdk_env.sh

# 7) 解析(SDK 自动下载 PP-DocLayoutV3 版面模型)
bash 40_parse.sh /path/to/doc.pdf ./out
#    带 Jev 质检:JEV_ENABLED=true bash 40_parse.sh /path/to/doc.pdf ./out

# 8) 冒烟测试(健康检查 + 显存占用 + 示例图端到端)
bash 50_smoke_test.sh
```

首次解析前建议先跑 `50_smoke_test.sh` 确认引擎可用。

## 配置

复制 `env.16g.example.sh` 为 `env.local.sh`(已被 gitignore)后按需修改;所有脚本启动时自动加载。未创建时脚本用内置默认值——默认值即 16G 推荐值。高频项:

| 变量 | 默认 | 说明 |
|---|---|---|
| `OCR_CTX` | 8192 | 1.0 引擎上下文;显存富余可升 16384 |
| `JEV_CTX` | 16384 | Jev 引擎上下文;官方示例 32768,共卡 16G 建议降档 |
| `LAYOUT_DEVICE` | cpu | 版面检测设备;`cuda:0` 需 30 号脚本以 GPU 模式装 paddle |
| `JEV_ENABLED` | false | `40_parse.sh` 是否启用 Jev 评分门控 |
| `HF_ENDPOINT` | 官方源 | 下载慢可设 `https://hf-mirror.com` |

## 脚本清单

| 脚本 | 作用 |
|---|---|
| `00_check_gpu.sh` | 环境体检:GPU/显存/驱动/磁盘/工具链 |
| `10_build_llamacpp.sh` | 克隆并编译 llama.cpp(GGML_CUDA=ON,产出 llama-server/llama-quantize) |
| `11_download_weights.sh` | 下载 1.0 GGUF(HF,支持镜像)与 Jev 原始权重 |
| `12_convert_jev_gguf.sh` | Jev HF→GGUF 转换(architectures 改为分类头,按官方文档流程) |
| `20_start_ocr_engine.sh` | 起 1.0 llama-server(pid/日志落 `../run/`) |
| `21_start_jev_engine.sh` | 起 Jev llama-server |
| `22_setup_jev_render_env.sh` | 装 Jev 评分服务渲染环境(调用上游 setup_render.sh) |
| `23_start_jev_service.sh` | 起 Jev 内置渲染器评分服务(/v1/rm/score*) |
| `30_setup_sdk_env.sh` | 建 SDK venv:minicpm-ocr[all]==1.0.2 + paddle(CPU/GPU 二选一) |
| `40_parse.sh` | 一键解析 PDF/图片 → Markdown(串行模式,可带 Jev) |
| `50_smoke_test.sh` | 健康检查 + 显存快照 + 示例图端到端 |
| `90_stop_all.sh` | 按 pid 停止本包启动的全部服务 |

## 已知边界与排障

- **400/静默重试类问题**:llama.cpp 路径不涉及 vLLM 的 `--trust-request-mm-kwargs` 与 chat template 参数,GGUF 内嵌模板已关闭 thinking,无需额外设置。
- **首次解析卡在下载**:版面模型(约几百 MB)来自 Paddle 官方地址,网络受限时手动下载 `PP-DocLayoutV3_infer.tar` 解压后 `export OCR_LAYOUT_MODEL_DIR=/path/to/PP-DocLayoutV3_infer`。
- **解析挂死先看引擎日志**:`../run/logs/*.log`;再 `curl http://127.0.0.1:18601/health`。
- **DSpark 无效是正常的**:llama.cpp 路径不支持投机解码,`50_smoke_test.sh` 不做该检查。
- 上游脚本(`sdk/scripts/`、`scripts/minicpm-ocr-jev/`)与本包并存:本包不修改上游文件,`22/23` 号脚本直接调用上游入口(只读使用,符合协作规则)。
