# Jev 引擎启停指南(16G 单卡 · deploy-16g 脚本包)

| 项 | 内容 |
|---|---|
| 适用环境 | 16 GB 显存单卡(RTX 5080 实机验证),1.0 引擎与 Jev 共卡、无并发 |
| 脚本位置 | `workspace/deploy-16g/`(下文所有命令默认已 `cd` 到该目录) |
| 关联文档 | [16G 可行性评估](../records/2026-10-29-16G显存跑OCR可行性评估.md) · [deploy-16g README](../../workspace/deploy-16g/README.md) · 上游 [llamacpp_deploy_jev_zh](../../docs/llamacpp_deploy_jev_zh.md) |
| 编写日期 | 2026-10-29 |

> 说明:本文档属于协作文档,按协作规则 v1.4 存放于 `new-docs/guides/`(上游 `docs/` 为只读快照,不做协作改动)。

## 1. Jev 是什么,什么时候需要启停

Jev(MiniCPM-OCR-1.0-Jev)是 MiniCPM-OCR 的**判别/质检模型**:在 1.0 解析引擎产出 Markdown 之后,它对每个版面块的渲染图与识别结果做评分,给出"免检 / 需复核 / 需重识别"的门控结论,从而在不牺牲质量的前提下减少人工校对量。它不是解析的必需组件——只跑 1.0 解析(最小路径)时完全不需要启动 Jev。

在 16G 单卡场景下,Jev 以两个服务的形式与 1.0 引擎共卡运行:一个是 **Jev 引擎**(llama-server 加载 bf16 GGUF,端口 18602,负责评分前向),另一个是 **Jev 评分服务**(内置渲染器 + precheck + 前向调度,端口 18500,即 SDK 对接的 `/v1/rm/score*` 端点)。两个服务都要起来,解析时的 Jev 质检才能工作;启动顺序必须是**先引擎、后评分服务**(23 号脚本会自检 21 号是否已就绪)。

典型的启停节奏:日常解析不需要 Jev 时,只保留 1.0 引擎(实机常驻约 3.9 GB 显存);需要质检质量对比或正式交付校验时,再按本文第 4 节把 Jev 两个服务拉起,用完按第 6 节只停 Jev、保留 1.0。这种"按需起停"也是共卡显存吃紧时的推荐做法。

## 2. 服务拓扑与端口速查

| 服务 | 启动脚本 | 地址 | 健康检查 | pid 文件 | 日志 |
|---|---|---|---|---|---|
| 1.0 解析引擎 | `20_start_ocr_engine.sh` | `127.0.0.1:18601` | `curl http://127.0.0.1:18601/health` | `../run/ocr-engine.pid` | `../run/logs/ocr-engine.log` |
| Jev 引擎 | `21_start_jev_engine.sh` | `127.0.0.1:18602` | `curl http://127.0.0.1:18602/health` | `../run/jev-engine.pid` | `../run/logs/jev-engine.log` |
| Jev 评分服务 | `23_start_jev_service.sh` | `127.0.0.1:18500` | `curl http://127.0.0.1:18500/healthz` | `../run/jev-service.pid` | `../run/logs/jev-service.log` |

要点:

- 三个服务均以后台进程运行(nohup + pidfile),启动脚本内置健康轮询:引擎最多等约 3 分钟,评分服务最多等约 2 分钟;超时会打印日志末尾 20 行并退出。
- `21/23` 号脚本都有**防重复启动**保护:检测到 pid 文件对应的进程仍在运行时,会提示"先执行 bash 90_stop_all.sh"并退出,不会拉起第二个实例。
- 评分服务(23 号)启动前会做两项前置自检:渲染环境 venv 不存在 → 提示先跑 22 号;Jev 引擎 `/health` 不通 → 提示先跑 21 号。因此按顺序执行时不会出现"服务起了但引擎没起"的中间态。

## 3. 首次启用前的一次性准备

如果此前只走过最小路径(`SKIP_JEV=true`),启用 Jev 前需要补齐三件事:**Jev 原始权重 → GGUF 转换 → 渲染环境**。这三步都只需做一次(脚本全部幂等,重复执行会自动跳过已完成部分),之后日常启停只涉及第 4 节的两条命令。

```bash
# (1) 补下 Jev 原始权重(约 4–5 GB;幂等:1.0 权重已存在则自动跳过,只补 Jev)
bash 11_download_weights.sh
#    慢网建议先开镜像: export HF_ENDPOINT=https://hf-mirror.com
#    产物: ../jev-hf/openbmb/MiniCPM-OCR-1.0-Jev/(HF 原始权重)

# (2) 转 GGUF(首次约 10–20 分钟;CPU 即可,不占显存)
bash 12_convert_jev_gguf.sh
#    产物: ../gguf/MiniCPM-OCR-Jev-bf16.gguf + ../gguf/mmproj-MiniCPM-OCR-Jev-bf16.gguf
#    关键点:转换器要求 config.json 的 architectures 为分类头
#    (MiniCPMOCRForSequenceClassification),脚本自动建软链目录完成改写,原目录不动。

# (3) 渲染环境(Pillow/playwright 固定版本 + Node + CJK 字体 + Chromium,较慢)
bash 22_setup_jev_render_env.sh
#    产物: ../venv-render/
#    慢网可先: export PIP_INDEX_URL=https://pypi.tuna.tsinghua.edu.cn/simple
#               export PLAYWRIGHT_DOWNLOAD_HOST=https://npmmirror.com/mirrors/playwright
```

三步全部完成后,`ls ../gguf/` 应能看到两个 `*Jev*` 文件,`../venv-render/bin/python -c 'import playwright, PIL'` 应无报错。另外建议先 `cp env.16g.example.sh env.local.sh` 建立本地配置(已被 gitignore),Jev 相关参数(`JEV_CTX`、`JEV_SERVICE_PORT` 等)的默认值即 16G 共卡推荐值,不改也能直接用。

## 4. 启动步骤

### 4.1 日常启动(两步)

假设 1.0 引擎已在运行(如当前实机:常驻约 3.9 GB 显存),启动 Jev 只需两条命令:

```bash
# 第 1 步:起 Jev 引擎(拉起后自动轮询 /health,最多约 3 分钟)
bash 21_start_jev_engine.sh
#    预期输出:"就绪: http://127.0.0.1:18602/health(pid xxx)"
#    随后提示下一步: bash 23_start_jev_service.sh

# 第 2 步:起 Jev 评分服务(自动轮询 /healthz,最多约 2 分钟)
bash 23_start_jev_service.sh
#    预期输出:"就绪: http://127.0.0.1:18500/healthz"
#    以及 SDK 对接提示:40 号脚本设 JEV_ENABLED=true 即可
```

如果 1.0 引擎也没在跑(例如刚重启机器),先补一步 `bash 20_start_ocr_engine.sh`,再执行上面两步。若 CUDA Toolkit 安装在 conda 环境里(当前实机即如此),启动前先 `conda activate minicpmocr`,否则可能报 `libcudart.so.12: cannot open shared object file`。

两个服务启动后的显存增量约 **5–8 GB**(bf16 权重约 5 GB + KV cache,ctx 16384),叠加 1.0 引擎后整机约 **9–14 GB**,在 16G 卡的安全范围内;实测基线见第 7 节。

### 4.2 启动后验证

```bash
# (a) 两个健康端点都通
curl -s http://127.0.0.1:18602/health   # Jev 引擎,返回 ok/true 类即通
curl -s http://127.0.0.1:18500/healthz  # 评分服务,预期含 "status": "ok"

# (b) 显存符合预期(两引擎共卡约 9–14 GB)
nvidia-smi --query-gpu=memory.used,memory.total --format=csv

# (c) 跑一次带 Jev 的解析,端到端确认(见第 5 节)
JEV_ENABLED=true bash 40_parse.sh ../../scripts/minicpm-ocr-jev/examples/01_text_putnam/block.png ./out-jev
```

带 Jev 的解析日志中会出现 `Jev 质检已启用(rm_url=http://127.0.0.1:18500,ternary)` 字样;解析产物目录里除 Markdown 外还会有各块的评分记录。另外,`50_smoke_test.sh` 的健康检查清单里有一项 Jev 引擎状态:最小路径下显示 `[–] Jev 引擎未启动(可选)` 属**预期**,不算失败;启动 Jev 后再跑会显示 `[✓]`。

## 5. 解析时启用 Jev 质检

Jev 服务本身只是"常驻待命",真正在解析流水线里生效,需要在 40 号解析命令上打开 `JEV_ENABLED=true`:

```bash
JEV_ENABLED=true bash 40_parse.sh /path/to/doc.pdf ./out
```

该开关等价于在 SDK 配置中设置 `tts.enabled=true`、`tts.rm_url=http://127.0.0.1:18500`、`tts.rm_input_form=ternary`。40 号脚本在启用时会先探测 `18500/healthz`,不通则直接报错"Jev 评分服务未就绪——先起 21/23 号脚本",不会带着坏配置跑完再失败。不加该开关(或显式 `JEV_ENABLED=false`)时,解析行为与最小路径完全一致,Jev 服务即使开着也不参与。

若想每次解析默认带 Jev,不必每次敲前缀:把 `env.16g.example.sh` 复制出的 `env.local.sh` 中 `JEV_ENABLED` 改为 `"true"` 即可,所有脚本都会自动加载该文件。需要临时关闭时,用 `JEV_ENABLED=false bash 40_parse.sh ...` 单次覆盖即可。

## 6. 关闭步骤

### 6.1 只停 Jev,保留 1.0 引擎(推荐日常操作)

```bash
bash 90_stop_all.sh jev
```

`jev` 是名称过滤参数,按 pid 文件名做子串匹配,会同时命中 `jev-engine` 与 `jev-service` 两个服务并依次停止,1.0 引擎(`ocr-engine`)不受影响。停止机制:先发 `SIGTERM`,给进程最多 10 秒优雅退出,超时补 `kill -9`;随后删除对应 pid 文件,防止残留 pid 影响下次启动。

### 6.2 全部停止

```bash
bash 90_stop_all.sh        # 不带参数:停 ocr-engine + jev-engine + jev-service
bash 90_stop_all.sh ocr    # 只停 1.0 解析引擎
```

全部停止适用于收工、释放显存跑其他任务、或需要单独重启某个引擎的场景。注意 90 号**只按 pid 文件停本脚本包拉起的服务**,不清理其他来源的 GPU 进程。

### 6.3 关闭后确认

```bash
nvidia-smi | grep -E 'llama|python'   # 90 号脚本执行完也会主动提示这条
ls ../run/*.pid 2>/dev/null           # 应看不到 jev-*.pid(90 号已清理)
```

确认 `nvidia-smi` 中已无对应的 `llama-server` 进程、显存回落(只停 Jev 后应回落到 1.0 引擎独占的约 4 GB 水位)即关闭完成。若发现 pid 文件还在但进程已死,属正常残留,下次启动对应脚本时会自动按"未在运行"处理并清理。

## 7. 显存预算与 OOM 降档

16G 单卡共卡方案的显存预算(估算与实测):

| 组件 | 常驻显存 | 备注 |
|---|---|---|
| 1.0 引擎(F16 GGUF,ctx 8192) | 实测 **≈3.9 GB**(RTX 5080) | 估算口径 4–6 GB,实机优于估算 |
| Jev 引擎(bf16 GGUF,ctx 16384) | 估算 ≈5–8 GB | 官方环境要求 ≥8 GB |
| 版面模型 PP-DocLayoutV3 | 0(默认 CPU) | `LAYOUT_DEVICE=cuda:0` 时 +1–2 GB |

两引擎常驻时按 12–14 GB 预算,余量约 2–4 GB。若启动 Jev 后遇到 OOM,按以下顺序降档:① `JEV_CTX` 16384 → 8192(改 `env.local.sh` 后重启 Jev 引擎生效);② 再不够,`OCR_CTX` 8192 → 4096(重启 1.0 引擎生效);③ 版面模型保持 CPU 不动;④ 极端情况下改用"不同时常驻"策略——`bash 90_stop_all.sh` 全停后按需单起其一,用完再切。

## 8. 常见问题排障

- **`21/23` 号报"已在运行(pid xxx),先执行 bash 90_stop_all.sh"**:服务已在跑或 pid 文件残留。确实想重启就 `bash 90_stop_all.sh jev` 后重新执行;只是残留(进程已死)则直接重跑启动脚本即可,它会自动清理。
- **`23` 号报"渲染环境不存在"或"Jev 引擎未就绪"**:按提示先跑 22 号 / 21 号。23 号不做静默兜底,缺前置会立即退出,这是设计行为。
- **`21` 号起不来,日志报 `libcudart.so.12`**:CUDA Toolkit 在 conda 环境里而当前 shell 未激活。`conda activate minicpmocr` 后重跑,或 `export LD_LIBRARY_PATH=$CONDA_PREFIX/lib:$LD_LIBRARY_PATH`。
- **`23` 号 2 分钟内未就绪**:先看 `tail -50 ../run/logs/jev-service.log`。常见原因是首次启动 Chromium 初始化慢、或渲染依赖安装不完整(重跑 22 号)。
- **下载/安装阶段卡住**:权重走 `HF_ENDPOINT=https://hf-mirror.com`;渲染环境走 `PIP_INDEX_URL` + `PLAYWRIGHT_DOWNLOAD_HOST`(见第 3 节)。
- **`50_smoke_test.sh` 里 Jev 显示 `[–]`**:该项是"可选组件状态",最小路径(`SKIP_JEV=true`)下未启动属预期;启动 Jev 后重跑会变 `[✓]`。
- **想彻底重置 Jev**:停服务(第 6 节)→ 删 `../gguf/*Jev*` 重转 → 删 `../venv-render` 重装 22 号 → 删 `../jev-hf` 重下(一般不需要走到这一步)。

## 9. 命令速查表

| 场景 | 命令 |
|---|---|
| 首次启用:补权重 | `bash 11_download_weights.sh` |
| 首次启用:转 GGUF | `bash 12_convert_jev_gguf.sh` |
| 首次启用:装渲染环境 | `bash 22_setup_jev_render_env.sh` |
| 日常:起 Jev 引擎 | `bash 21_start_jev_engine.sh` |
| 日常:起评分服务 | `bash 23_start_jev_service.sh` |
| 日常:带 Jev 解析 | `JEV_ENABLED=true bash 40_parse.sh <输入> [输出目录]` |
| 验证引擎/服务 | `curl http://127.0.0.1:18602/health` / `curl http://127.0.0.1:18500/healthz` |
| 停 Jev(保留 1.0) | `bash 90_stop_all.sh jev` |
| 全部停止 | `bash 90_stop_all.sh` |
| 只停 1.0 引擎 | `bash 90_stop_all.sh ocr` |
| 关闭后自查 | `nvidia-smi \| grep -E 'llama\|python'` |
| 看日志 | `tail -50 ../run/logs/jev-engine.log` / `jev-service.log` |
