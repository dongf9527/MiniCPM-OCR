# deploy-16g 实机命令清单

| 项目 | 内容 |
|---|---|
| 日期 | 2026-10-30 |
| 适用环境 | CNBEJFSOP03 / RTX 5080 16G / Ubuntu 22.04 类 / conda py312 |
| 一句话 | `workspace/deploy-16g/` 脚本包 00→50 全链路的实机命令速查:首次部署、日常启停、解析、冒烟、停止、排障,并附闭环实测参考值 |
| 关联 | 《16G 显存跑 OCR 可行性评估》《部署链路闭环与共卡实测 2026-10-30》《Jev 引擎启停指南》《Jev 阈值业务校准指南》 |

所有命令在 `<仓库根>/workspace/deploy-16g/` 下执行;命令行与脚本实际接口、`deploy-16g/README.md`、2026-10-30 实机闭环记录三方核对一致。

## 0. 前提(每个新终端会话先执行)

```bash
conda activate py312
cd <仓库根>/workspace/deploy-16g
```

- conda 环境提供 nvcc 与 `libcudart.so.12`,起引擎(20/21 号)前必须激活;否则 20 号报 `libcudart.so.12: cannot open shared object file`。
- `env.local.sh` 可选(`cp env.16g.example.sh env.local.sh` 后按需修改),不创建则使用内置 16G 默认值——默认值即推荐配置。

## 1. 首次部署(一次性,完整路径)

```bash
# 0) 体检(预期均"未过 0 项")
bash 00_check_gpu.sh              # GPU/驱动/磁盘/工具链/nvcc/HF 连通性
bash 01_check_python_env.sh       # conda env/python 版本/pip/venv/nvcc

# 1) 编译 llama.cpp(RTX 50 系架构 120,需 nvcc ≥12.8;数分钟)
LLAMA_CUDA_ARCH=120 bash 10_build_llamacpp.sh    # 预期:产出 build/bin/llama-server

# 2) 权重(最小路径先跑通,再幂等补 Jev)
SKIP_JEV=true bash 11_download_weights.sh        # 1.0 GGUF 两个文件
bash 11_download_weights.sh                      # 补下 Jev 原始权重(幂等,已下的跳过)
bash 12_convert_jev_gguf.sh                      # Jev 转 GGUF,首次约 10–20 分钟

# 3) Jev 渲染环境(Chromium/Node/字体,较慢)
bash 22_setup_jev_render_env.sh

# 4) SDK 环境(预期"SDK ok")
bash 30_setup_sdk_env.sh
```

最小路径(仅 1.0 解析,不部署 Jev)只需:`00 → 01 → 10 → 11(SKIP_JEV=true) → 20 → 30 → 50`,省 4–5 GB 显存与 Jev 全套环境。

## 2. 日常启停(每次重启机器后)

```bash
bash 20_start_ocr_engine.sh    # 1.0 引擎  :18601,预期"就绪: http://127.0.0.1:18601/health"
bash 21_start_jev_engine.sh    # Jev 引擎  :18602
bash 23_start_jev_service.sh   # 评分服务  :18500,预期 announce 显示 127.0.0.1:18500
```

启动后验证(三端口健康 + 绑定洁净化 + 显存):

```bash
curl -s http://127.0.0.1:18601/health
curl -s http://127.0.0.1:18602/health
curl -s http://127.0.0.1:18500/healthz     # 预期 "status": "ok"
ss -tlnp | grep -E '18500|18601|18602'     # 应仅绑 127.0.0.1(23 号绑定不洁问题已于 e1eff01 修复并实机验证)
nvidia-smi --query-gpu=memory.used,memory.total --format=csv   # 共卡实测约 10274 MiB / 16303 MiB
```

## 3. 解析文件

```bash
# 纯解析(无 Jev,实测约 1.27 s/页)
bash 40_parse.sh /path/to/doc.pdf ./out

# 带 Jev 质检(评分门控)
JEV_ENABLED=true bash 40_parse.sh /path/to/doc.pdf ./out

# Jev 链路验证 / RM 耗时采集(单候选也强制送评)
JEV_ENABLED=true JEV_FORCE_SCORE=true bash 40_parse.sh /path/to/img.png ./out-jev
```

- 产物:`<输出目录>/<输入主名>.md`(40 号内部把"输出目录"翻译为 CLI 的目标 Markdown 文件路径);
- 中间产物(run_dir、results_json 等)统一收拢在 `workspace/runs/minicpmvocr_parse_<时间戳>/`;
- 输入建议给绝对路径——40 号已把输入/输出钉成绝对路径,但绝对路径可彻底避免歧义;
- 不带 `JEV_FORCE_SCORE` 时 JSON 摘要里 `rm_used: 0` 属预期:llamacpp 后端不支持多候选(`n` 参数被方言层丢弃),干净文本去重后单候选按 SDK 设计跳过 RM;要多候选择优需换 vLLM 后端;
- 阈值校准样本采集即用第三种模式,后续步骤见《Jev 阈值业务校准指南》。

## 4. 冒烟与停止

```bash
bash 50_smoke_test.sh            # 三项健康检查 ✓ + 显存快照 + 示例图端到端(预期落盘 block.md)

bash 90_stop_all.sh              # 全停(ocr-engine / jev-engine / jev-service)
bash 90_stop_all.sh jev          # 只停 Jev 两服务(引擎+评分),保留 1.0 引擎
bash 90_stop_all.sh service      # 只停评分服务(23 号)
bash 90_stop_all.sh ocr          # 只停 1.0 引擎
```

90 号按 pidfile(子串匹配 `workspace/run/*.pid`)停止,服务类日志统一在 `workspace/run/logs/`。

## 5. 排障速查

```bash
tail -n 50 ../run/logs/*.log              # 引擎/服务日志(先看这里)
curl -s http://127.0.0.1:18601/health     # 解析挂死先看 1.0 引擎是否存活
nvidia-smi                                # 显存与温度
```

- **首次解析卡在下载**:版面模型(PP-DocLayoutV3,125.8 MB)由 40 号首次解析时自动下载(官方 BOS 源,tar 缓存复用);网络受限时手动下载 `PP-DocLayoutV3_infer.tar` 解压后 `export OCR_LAYOUT_MODEL_DIR=/path/to/PP-DocLayoutV3_infer`。
- **PDF 解析长时间无输出属正常**:栅格化阶段静默 1–3 分钟;40 号已恢复逐页进度(每 5 页一条 `[infer] progress`)并按页数前置 ETA,`fitz` FutureWarning 已按消息前缀静音。
- **10 号报 `unsupported GNU version`**:nvcc 拒绝过新的宿主 g++,`conda install -c conda-forge gxx_linux-64=14` 或改装 `cuda-toolkit=12.9/13.0`。
- **20 号报 `libcudart.so.12`**:先 `conda activate py312` 再起引擎,或 `export LD_LIBRARY_PATH=$CONDA_PREFIX/lib:$LD_LIBRARY_PATH`。
- **DSpark 无效是正常的**:llama.cpp 路径不支持投机解码,50 号不做该检查。
- **OOM 降档顺序**:先降 `JEV_CTX`(16384→8192),再降 `OCR_CTX`(8192→4096),版面模型保持 CPU;极端情况两引擎不同时启动(90 号全停后按需单起)。

## 6. 实测参考值(2026-10-30 闭环数据,CNBEJFSOP03 / RTX 5080 16G)

| 项 | 值 | 说明 |
|---|---|---|
| 端口 | 18601 / 18602 / 18500 | 1.0 引擎 / Jev 引擎 / Jev 评分服务(均仅绑 127.0.0.1) |
| 共卡显存 | 10287 MiB(Jev 后) / 10274 MiB(冒烟后) / 16303 MiB 总量 | 余约 6.0 GB(37%),低于 12–14 GB 预算下沿 1.7 GB |
| 1.0 引擎单卡 | 3962 MiB(F16 GGUF,ctx 8192) | 权重 1.4 GB + mmproj 0.86 GB + KV cache |
| 版面模型 | 0 显存(CPU) | PP-DocLayoutV3 单页 detect 约 2.5 s |
| 页级推理 | 1.27 s/页(无 Jev)→ 4.60 s/页(带 Jev 强制评分) | 质检增量约 3.3 s/页;稀疏页口径(2 块/页) |
| 多页 PDF(块密集) | 5.1 s/页 + 版面 2.1 s/页(22.8 块/页,0.22 s/块) | djfyj.pdf 25 页/571 块实测;页级 ≈ 版面 2.1 s + 块数 × 0.22 s |
| RM 单块耗时 | 1.57 s(渲染 1.98 s 占 63% + 引擎前向 1.14 s,合计 3.14 s) | 渲染(CPU katex)是 QPS 优化第一抓手 |
| 驱动/CUDA | 620.67.01 / CUDA UMD 13.5 | 空闲 util 2%–16%、37–38 °C |

## 7. 备忘

- 官方 Q8_0 GGUF 已发布:可替换 12 号自转权重(观察项,替换后重跑 20 号启动 + 50 号冒烟对比)。
- GitHub token 约 2026-11-28 到期,到期前重签。
- 41 号阈值校准工具已就绪(`python3 41_jev_threshold_report.py scores.jsonl --target-err 0.005`),依赖自有标注样本(《Jev 阈值业务校准指南》三步法)。
