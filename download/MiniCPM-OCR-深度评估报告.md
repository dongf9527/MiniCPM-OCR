# MiniCPM-OCR 深度评估报告

| 项目 | 内容 |
|---|---|
| 评估对象 | [OpenBMB/MiniCPM-OCR](https://github.com/OpenBMB/MiniCPM-OCR)(commit `b33b474`,2026-10-28) |
| 评估日期 | 2026-10-29 |
| 评估方式 | 仓库全量克隆走读 + 官方文档/模型卡/第三方报道交叉验证 |
| 目标读者 | 技术团队(本地私有化部署、文档结构化/RAG/微调方向) |
| 报告版本 | v1.1(深度评估;增补 1.0/Jev 双模型详细对比与典型用法) |

---

## 1. 执行摘要

MiniCPM-OCR 是面壁智能(OpenBMB)于 **2026-10-27 刚刚发布的开源 OCR 专用模型家族**,由两个模型组成:**MiniCPM-OCR 1.0(1.3B,文档解析)** 和 **MiniCPM-OCR Jev(2B,OCR 结果正确性判别)**。整个项目——包括代码、文档和全部模型权重——以 **Apache 2.0** 协议开源,可自由商用。

核心结论:

1. **能力**:官方自报成绩在 Real5-OmniDocBench(93.68)、OCRBench v2(54.7)等四项文档解析基准上居开源第一梯队;解析吞吐 1.2 pages/s(RTX 5090),约为 PaddleOCR-VL-1.6 的 1.49 倍。任务覆盖文本、表格、公式、图表、印章识别与关键信息抽取(KIE),中英双语,对扫描、弯曲、拍照、翻拍等低质输入做了专门优化。
2. **最大亮点**:Jev 判别模型。2B 参数即达到接近 397B 大模型的判别精度(AUROC 93.6 vs Qwen3.5-397B 93.8),且可跨解析器复用,为"自动化 + 人工复核"的生产管线提供了现成的置信度门控组件——这是当前开源 OCR 方案中少见的差异化能力。
3. **部署**:本地私有化友好,但**标准 vLLM 路径显存门槛 ≥24 GB、NVIDIA 驱动 ≥580(CUDA 13)**,且 vLLM 需编译官方 feat-ocr 源码分支(96 核约 20–40 分钟);低配场景可走 llama.cpp/GGUF(权重共 2.3 GB,CPU 也能跑)或 Apple Silicon MLX。
4. **风险**:项目发布仅 2 天,文档中仍有版本占位符(`xxx`),基准成绩均为官方自报、尚无独立第三方复现,语种以中英为主;早期采用需锁定版本、预留试错成本。
5. **建议**:与贵方三个业务方向(结构化提取、RAG、微调)匹配度高,**值得立即启动 POC**,路线图见第 11.2 节。

---

## 2. 项目概况与模型家族

### 2.1 基本信息

| 维度 | 内容 |
|---|---|
| 仓库 | github.com/OpenBMB/MiniCPM-OCR(Python) |
| 首次发布 | 2026-10-27,评估时最新提交 2026-10-28 |
| 社区热度 | 发布 2 天内 Star 数百(快速增长期);HuggingFace 261 likes |
| 许可证 | **Apache 2.0**(代码 + 文档 + 权重全量) |
| SDK | PyPI 包 `minicpm-ocr`(SDK 1.0.2,导入名 `minicpmvocr`) |
| 权重分发 | HuggingFace + ModelScope 双渠道 |
| 配套设施 | 免费 API、在线 Demo(国内/海外)、SKILL.md(Agent 一键部署)、Web UI/Docker |

MiniCPM-OCR 1.0 是 **MiniCPM-V/o 家族第一个 OCR 专用模型**,基于 MiniCPM-V 4.6 做 OCR 特化训练,架构为 **SigLIP 视觉编码器 + Qwen3.5 语言模型**(需配套 Transformers 5 适配)。视觉侧采用 4× 视觉 token 压缩,`scale_resolution` 448、最多 9 切片,兼顾分辨率与推理成本。

### 2.2 双模型架构:"解析 + 判别"闭环

这是本项目区别于其他开源 OCR 的核心设计。生产环境中 OCR 错误很少"响亮地失败"——把 6 认成 8、漏掉表格一行,输出看起来毫无异常。MiniCPM-OCR 的思路是让另一个小模型专门回答"哪里可能错了"。一个形象的类比:**1.0 是"答题的学生",Jev 是"批改卷子的质检员"**——两者独立部署、各司其职,Jev 不能替代 1.0 产出内容,1.0 也不自带质检能力。

两个模型的详细对比:

| 维度 | MiniCPM-OCR 1.0(解析) | MiniCPM-OCR Jev(判别) |
|---|---|---|
| 模型定位 | OCR 专用解析模型,生成式 VLM | OCR 结果质量判别模型,判别式 |
| 参数量 | 1.3B | 2B |
| 基座与结构 | SigLIP 视觉编码器 + Qwen3.5 语言模型(基于 MiniCPM-V 4.6 做 OCR 特化训练) | Qwen3.5-2B,**将 `lm_head` 输出头替换为二分类头** |
| 输入 | 整页文档 / 版面切块图像 | 三元组:①区域原图 ②OCR 候选文本 ③由该文本生成的渲染图(一一对应) |
| 输出 | Markdown 文本、HTML 表格、LaTeX 公式、印章文字、KIE JSON | **0–1 质量评分**(分数越高越倾向判为识别正确),不产出任何正文内容 |
| 工作粒度 | 整页 / 单个区域 | 单个区域(仅文本、公式、表格三类) |
| 核心任务 | 文本/表格/公式/图表/印章识别 + 关键信息抽取(KIE) | 判断候选结果是对是错 |
| 基准成绩 | Real5-OmniDocBench 93.68 等四项解析基准第一梯队 | JevOCRBench AUROC 93.6,反超 35B 级模型、逼近 397B 模型 |
| 流水线角色 | 主力解析,需配 PP-DocLayoutV3 版面模型 + SDK 组装 | 可选质检环节,**不依赖版面模型**,接在任意解析器之后即可 |

两者可独立使用:Jev 明确支持搭配 **MiniCPM-OCR 1.0、GLM-OCR、PaddleOCR-VL-1.6、Xiaomi-OCR-0** 等其他解析器的输出,这意味着已用其他方案积累的管线也能叠加 Jev 做质量门控。

一个关键边界:Jev 只输出"分数"而非"修正后的文本"——**它只能筛错、不能纠错**;且分数是排序信号(AUROC 口径),不是校准过的正确概率,不能直接当置信度使用,阈值需在业务样本上另行标定(详见 3.4 节)。

### 2.3 模型规格与权重

| 模型 | 参数量 | 提供格式 | 说明 |
|---|---|---|---|
| MiniCPM-OCR 1.0 | 1.3B(实测 1.300B) | BF16 / GGUF / AWQ(W4A16) / GPTQ(W4A16) | 主模型 |
| ├─ DSpark 采样头 | — | BF16 / GGUF | 投机解码草稿模型,须与主模型同版本配套 |
| MiniCPM-OCR Jev | 2B | BF16 / GGUF / AWQ / GPTQ | 判别模型 |

权重体积参考:BF16 主模型约 3 GB;GGUF 为 F16 语言模型 1.4 GB + 视觉投影器(mmproj-4x)859 MB,共约 2.3 GB;官方 Q4_K_M/Q8_0 量化版"即将提供",当前可用 `llama-quantize` 自行量化。

---

## 3. 功能特点

### 3.1 完整解析流水线

单靠 1.3B 的 VLM 无法直接高质量解析整页文档,官方方案是 **SDK + 版面模型 + VLM** 的三件套:

```
PDF/PNG/JPG ──► PP-DocLayoutV3 版面分析(区域检测 + 阅读顺序)
                     │
                     ▼
              SDK 按区域切块 ──► 并发调用 MiniCPM-OCR 1.0 识别各区域
                     │
                     ▼
        按阅读顺序组装 Markdown:表格 OTSL→HTML、公式保留 LaTeX
                     │
                     ▼   (可选)
        MiniCPM-OCR Jev 逐区域评分 ──► 自动通过 / 人工复核 / 多模型择优
```

架构上,SDK(版面检测、切块、拼接、并发调度)与推理服务(vLLM 等)是**两个独立 Python 环境**,可以部署在不同机器上——SDK 机器甚至不需要 GPU,通过 `--server-url` 或 SSH 隧道连接远程推理服务。官方强调按此教程部署后**文档处理全程本地完成**,不依赖云端 OCR,适合数据不出域的私有化场景。

### 3.2 覆盖的识别任务

模型按区域类型使用固定提示词,API 直调即可获得对应输出(SDK 内部自动分派):

| 区域类型 | 提示词 | 输出 | SDK token 预算 |
|---|---|---|---|
| 正文/标题/脚注等 | `Text Recognition:` | 纯文本 | 512–4096 |
| 表格 | `Table Recognition:` | OTSL(SDK 转 HTML) | 8192 |
| 公式 | `Formula Recognition:` | LaTeX | 2048 |
| 印章 | `Seal Recognition:` | 印章文字 | 256 |
| 图表 | `Chart to Table:` | 表格(HTML) | 4096 |

SDK 的提示词表(`DEFAULT_PROMPT_MAP`)对 20+ 种版面元素(标题、参考文献、竖排文字、页眉页脚、算法块等)预置了识别提示词、输出格式与 token 上限,并允许通过外部 YAML 完全自定义——这是二次开发最常用的入口之一。Markdown 组装规则(标题层级、公式包裹格式、需忽略的元素)同样可配置。

### 3.3 KIE 关键信息抽取

1.0 支持按字段名直接从图片抽取结构化信息,**无需先生成全文 Markdown**,适合票据、单据类场景:

```text
Extract the "店名", "金额". Format the output as a JSON object
with keys: "店名", "金额". If an item is not in the image, use "###".
```

返回 JSON 文本,字段名可中英文。注意返回内容是模型生成的字符串,接入下游程序前应解析并校验(该机制本质是 prompt 驱动,无 schema 约束,生产使用建议配合解析容错与人工抽检)。

### 3.4 Jev 的典型用法

"解析 → 质检"的接入位置在解析器之后、下游业务之前。官方文档给出的标准数据流分四步:

1. **保留元信息**:解析文档时保留页面/区域标识、区域原图、区域类别(`text`/`formula`/`table`)及 OCR 候选文本;
2. **提交评分**:将原图 + 类别 + 候选文本交给 Jev 服务(云端 API、Docker 或内置渲染器的 SDK 服务会自动完成渲染;不带渲染器的 SDK 部署需调用方自备渲染图);
3. **阈值分发**:检查返回 `verdict` 后,将有效评分与候选关联,按业务阈值分配"自动通过 / 人工复核";
4. **顺序输出**:按原阅读顺序输出选定结果,保留待复核区域供回看原文。

API 层面提供三种调用粒度:`score`(单候选打分)、`score_best`(单块多候选选优)、`score_best_batch`(多块批量选优)。

**场景一:自动门控,减少人工复核**。对解析结果的每个区域评分,高于阈值自动进入下游流程,低于阈值转人工队列。官方给出法律文书、财务票据、复杂文档三类"免检比例-准确率"曲线:提高阈值会减少自动通过数量、提升免检准确率,反之亦然,需在两者间按业务容错线取舍。官方同时明确提示:AUROC 只说明排序能力,**阈值必须在自家业务样本上标注校准**,分数不能直接解释为正确概率;解析器或文档分布改变后应重新验证。

**场景二:多模型择优,提升解析质量**。基于同一份版面分割结果,让多个 OCR 引擎各识别一遍,Jev 对同一区域的多个候选打分,选分数最高者按阅读顺序组合输出;若所有候选均低于业务阈值,该区域仍转人工。实测可为 MiniCPM-OCR 1.0、Xiaomi OCR、PaddleOCR-VL 1.6 各自带来 Overall 增益。注意约束:同一区域的候选需使用**一致的裁片与内容范围**;Jev 只能从已有候选中择优,最终质量上限取决于候选结果的覆盖与正确性。

**场景三:跨解析器复用**。对 MiniCPM-OCR 1.0、GLM-OCR、PaddleOCR-VL-1.6、Xiaomi-OCR-0 四种已验证解析器的输出,AUROC 稳定在 91.9–93.4(最大差 1.5 分),泛化性有官方数据背书——已有 PaddleOCR/GLM-OCR 产能的团队可免改造叠加 Jev 做质量增强。

使用时需先检查返回的 `verdict` 字段:只有 `scored` 才是真实模型评分;`precheck_reject`(如 LaTeX 语法坏)/`render_error` 等固定返回 0.0,`encode_error`/`forward_error` 返回 -1.0,均不能当作"低分"参与比较。

---

## 4. OCR 识别能力评估

### 4.1 文档解析基准

官方引用的六项基准成绩(数值为项目方自报,详见 4.4 节可信度讨论):

| 基准 | MiniCPM-OCR 1.0 | 说明 |
|---|---:|---|
| Real5-OmniDocBench | **93.68** | 对 OmniDocBench 全部 1355 页做物理重建(扫描/弯曲/翻拍/光照/倾斜 5 场景)的真实鲁棒性基准;官方榜当前第一为 PaddleOCR-VL-1.6(93.19) |
| Wild-OmniDocBench | 92.39 | 野外真实文档 |
| OmniDocBench v1.6 | 96.51 | 综合文档解析 |
| olmOCR-Bench | 82.7 | AI2 英文解析基准 |
| OCRBench v2 | **54.7** | 通用 OCR 能力 |
| CHAOS-Bench | 29.78 | 项目方引用的补充评测轴 |

横向对比(数据源:仓库 `benchmark-table.html` / `benchmark-data.json`,部分为官方文档表格):

| 模型 | 参数量 | Real5 | Wild | v1.6 | olmOCR | OCRBench v2 | 吞吐(pages/s) |
|---|---:|---:|---:|---:|---:|---:|---:|
| **MiniCPM-OCR 1.0** | 1.3B | **93.68** | **92.39** | 96.51 | **82.7** | **54.7** | **1.217** |
| PaddleOCR-VL-1.6 | 0.9B | 93.19 | 91.49 | 96.34 | 80.2 | 35.2 | 0.818 |
| Xiaomi-OCR-0 | 0.8B | 92.73 | 92.06 | 96.83 | 82.1 | 47.0 | 0.724 |
| GLM-OCR | 0.9B | 90.32 | 90.40 | 95.22 | 75.2 | 45.5 | 1.179 |
| MinerU2.5-Pro | 1.2B | 89.94 | 90.06 | 95.69 | 79.5 | 29.1 | 0.336 |
| HunyuanOCR-1.5 | 1B | 88.70 | 87.01 | 94.74 | 78.6 | 45.0 | 0.416 |

要点解读:

- **质量与速度同时领先(自报口径)**:在 1B 级专用模型中,MiniCPM-OCR 1.0 六轴全面第一;第三方数据源(gawron 2026-07 榜)中 PaddleOCR-VL-1.6(0.9B,96.33)原为 v1.6 榜首,MiniCPM 的 96.51 若成立则小幅超越,但该数字尚待独立复现。
- **吞吐实测条件明确**:RTX 5090、OmniDocBench v1.6 全量 1651 图、图片级并发 1、各模型均用加速配置。并发 8 时可达 **2.133 pages/s**(1.75× 加速比),多并发扩展性尚可。
- **DSpark 投机解码**:端到端效率 +55%,验证环境接受长度(accept length)5.2–7.0。这是需要主模型 + 草稿头配套的解码加速,对吞吐敏感的批量场景是默认推荐配置。
- **通用 OCR(OCRBench v2 54.7)领先幅度最大**,说明其不止会"读整页文档",单图通用识别(手写、招牌等)能力也在第一梯队。

### 4.2 Jev 判别能力

JevOCRBench(AUROC ×100,越高越好):

| 模型 | 参数量 | Overall | Text | Formula | Table |
|---|---:|---:|---:|---:|---:|
| **MiniCPM-OCR Jev** | **2B** | **93.6** | 94.6 | 93.1 | 91.1 |
| Qwen3.5(未特化) | 2B | 50.6 | 50.7 | 50.2 | 50.6 |
| Qwen3.5 | 9B | 72.0 | 75.9 | 67.7 | 73.4 |
| JEV | 35B·A3B | 90.1 | 91.6 | 88.9 | 89.6 |
| Gemma 4 | 31B | 90.5 | 91.0 | 90.8 | 87.7 |
| Qwen3.5 | 397B·A17B | 93.8 | 95.4 | 91.8 | 91.4 |
| Kimi K3 | 2.8T·A104B | 96.9 | 97.1 | 96.0 | 97.0 |
| Gemini 3.8 Flash | 闭源 | 97.1 | 97.2 | 98.0 | 95.7 |

同基座 2B 未特化只有 50.6(相当于随机),特化后 93.6、**反超 35B 级模型、逼近 397B 模型**——判别任务对模型规模的依赖远小于通用能力,2B 的定位选择非常经济。跨解析器 AUROC 91.9–93.4 进一步支撑"即插即用"的宣传。需要注意:该基准本身由项目方构建并发布(HuggingFace `openbmb/JevOCRBench`),样本分布未必覆盖贵方文档类型。

### 4.3 能力边界与数据可信度(重要)

- **语种**:官方仅承诺中英双语。其他语种官方用"法语手写行识别"作为微调教学案例,侧面说明非中英语种需自行微调验证。
- **自报数据**:Real5/Wild/JevOCRBench 均为项目方自建或自报,截至评估日,Real5 官方排行榜尚未收录 MiniCPM-OCR 1.0,第三方独立复现未见。仓库内 `benchmark-data.json` 亦标注部分分数为 `pending_confirmation`。
- **工程文档中的未定项**:`vllm_deploy.md` 中 vLLM/Transformers 版本号仍是 `xxx` 占位符,部分能力(如 Jev 云端 API)标注"即将提供",反映项目处于发布初期,快速迭代中。
- **API 直出的局限**:表格直出为 OTSL 需 SDK 转 HTML;KIE 无 schema 校验;`finish_reason=length` 时输出被截断需自行调预算。

---

## 5. 部署要求(本地私有化视角)

### 5.1 环境与硬件门槛

| 项目 | 标准 vLLM 路径 | 低配路径(llama.cpp) |
|---|---|---|
| GPU 显存 | **≥24 GB**(官方门槛;验证机 RTX 5090 32GB) | 4–6 GB 即可,或纯 CPU |
| NVIDIA 驱动 | **≥580(CUDA 13)**;旧驱动需配 cuda-compat 兼容库(A100 等可前向兼容) | 无强制 |
| 系统 | Linux x86_64(Ubuntu 22.04 验证) | Linux/Windows/macOS |
| Python | 推理环境 3.13(vLLM)/ ≥3.10(transformers);SDK ≥3.10 | — |
| 磁盘 | **≥40 GB**(SDK GPU 环境约 9 GB、vLLM 环境约 8 GB、源码编译产物约 6 GB、模型约 3 GB,其余为缓存) | ≥10 GB |
| 内存 | 编译 vLLM 时按 MAX_JOBS 预留(147 GB 内存建议 8–32 jobs) | ≥16 GB |

### 5.2 标准部署架构(双环境)

官方标准形态是**两个 venv + 一次源码编译**:

1. **SDK 环境**:`pip install "minicpm-ocr[all]==1.0.2"` + `paddlepaddle-gpu==3.3.0` + `paddlex==3.4.2`,负责 PP-DocLayoutV3 版面检测(GPU/CPU 可选)、切块、并发调度、Markdown 组装。版面模型自动下载。
2. **推理环境**:PyPI 稳定版 vLLM **不支持** `minicpm_ocr` 架构,需执行 `bash scripts/install.sh vllm` 编译官方 **feat-ocr 分支 vLLM(commit `5c2b92a5dc`)+ feat-ocr transformers(`69eafbc5bd`,5.19.0.dev0)**,依赖 torch 2.14.0+cu130、gcc-13、nvcc 13.x 全家桶对齐。96 核机器全程约 20–40 分钟。
3. **启动**(DSpark 默认开启):

```bash
vllm serve openbmb/MiniCPM-OCR-1.0 \
  --served-model-name minicpm-ocr --port 18499 \
  --max-model-len 40960 --max-num-batched-tokens 40960 --max-num-seqs 32 \
  --limit-mm-per-prompt '{"image":36,"video":0}' \
  --attention-backend FLASH_ATTN --mm-encoder-attn-backend FLASH_ATTN \
  --mm-processor-kwargs '{"downsample_mode":"4x"}' \
  --gpu-memory-utilization 0.85 --trust-request-mm-kwargs \
  --speculative-config '{"method":"dspark","model":"openbmb/MiniCPM-OCR-1.0-DSpark",
                         "num_speculative_tokens":15,"enable_adaptive_verification":false}' \
  --default-chat-template-kwargs '{"enable_thinking":false}'
```

4. **解析**:`minicpmvocr parse --server-url http://127.0.0.1:18499 --model minicpm-ocr --input doc.pdf --output doc.md`。

不想编译 vLLM 的替代:Transformers serve(`tf-ocr-env`,性能低些但零编译)、SGLang、llama.cpp、Ollama,均有官方文档。

### 5.3 四种推理后端对比

| 后端 | 适配状态 | 显存需求 | 适用场景 |
|---|---|---|---|
| vLLM(feat-ocr 编译) | 官方默认,支持 DSpark 加速 | ≥24 GB | 生产批量解析、追求吞吐 |
| SGLang | 官方文档提供 | 类似 vLLM | 已有 SGLang 技术栈 |
| Transformers serve | 官方文档,零编译 | 24 GB 级 | 快速验证、双端逐字比对 |
| llama.cpp / Ollama | GGUF 开箱即用 | 4–6 GB / 纯 CPU | 边缘设备、低配 POC、离线终端 |

Apple Silicon 另有 MLX-VLM 方案(与 neywalabs 合作):M5 Max 上 prefill 6339 tok/s、decode 220–235 tok/s,Jev 单块判别中位延迟 62.9 ms;官方还演示了在 iPhone/iPad 上本地运行。

### 5.4 显存梯度与降配手段

| 方案 | 估算显存 | 代价 |
|---|---|---|
| vLLM BF16 + DSpark,ctx 40960 | 24 GB+(官方门槛) | 无 |
| vLLM 降参:ctx 16384 + util 0.7 | ~20 GB 级(官方 OOM 处置建议,估) | 上下文/吞吐收缩 |
| vLLM AWQ/GPTQ W4A16 | 待验证(权重约减半,估) | 需验证精度损耗 |
| llama.cpp F16 GGUF(GPU offload) | 4–6 GB(估) | 吞吐显著低于 vLLM |
| llama.cpp 纯 CPU(AVX2) | 0 GB(16 GB 内存) | 每页秒级~分钟级(估) |

### 5.5 高频踩坑清单(来自官方 FAQ,部署前必读)

1. **漏 `--trust-request-mm-kwargs`**:服务对带图请求静默返回 400,SDK 默默重试 600 秒,表现为"解析挂死"。
2. **漏 `enable_thinking:false`**(openai/transformers 后端):输出为空或乱码。vLLM 的 SDK 配置已内置。
3. **视频预热参数冲突**:需显式 `--limit-mm-per-prompt '{"image":36,"video":0}'`。
4. **CUDA 13 驱动**:`CUDA driver version is insufficient` → 驱动需 ≥580,或按官方步骤配 `cuda-compat-13-0`(A100 数据中心卡适用)。
5. **FlashInfer JIT 编译失败**:`Could not find nvcc`、`ptxas fatal` 等 → 按官方对齐 nvcc/nvrtc/nvjitlink 到 13.4.92 并补齐软链接;这些是当前最大运维摩擦点。
6. **首次启动 CUDA graph 捕获超时被 SIGTERM**:重启一次即可,仍失败加 `--enforce-eager`。
7. **版面检测报 CUDA 错误**:CPU 版 paddle 需加 `--set layout.device=cpu`;只解析图片也需要 `pypdfium2`。
8. **表格输出 `<otsl>`**:API 直调不转换,必须走 SDK 流水线或自行转换。
9. DSpark 生效验证:`curl /metrics | grep spec_decode_num`,观察 `accepted/drafts`,接受长度 5.2–7.0 为正常。

---

## 6. 硬件成本估算(本地私有化)

以下为 2026 年 Q4 市场参考价区间(估算值,采购前请询价):

| 档位 | 配置 | 参考成本 | 适配场景 |
|---|---|---|---|
| 零成本 POC | 免费云 API / 在线 Demo / 任意 ≥16 GB 内存服务器 + llama.cpp CPU | ¥0 | 业务样本可行性验证 |
| 低配 POC | RTX 4060Ti 16GB / 二手 3090 24GB + GGUF 或旧驱动兼容路径 | ¥2,000–6,000 | 小批量试跑、算法验证 |
| 标准生产(单卡) | **RTX 4090 24GB**(满足官方门槛) | ~¥1.3–1.8 万 | 中小批量,日处理数千页级 |
| 推荐生产(单卡) | **RTX 5090 32GB**(官方验证配置,余量充足) | ~¥2.3–3 万 | 吞吐压测与生产默认 |
| 高吞吐 | 2×5090 多实例 + SDK 多 `--server-url` 负载 | ~¥5–6 万 | 日处理数万页 |
| 临时弹性 | 云 GPU 按需租用(A100/4090 级) | ~¥2–15/时(估) | 突发批量、无采购预算 |

两点提示:① Jev(2B,约 5 GB)可与 1.0 共卡部署,不必单独采购;② 官方自报"每千页成本低于 1 美元"是研究者口径,实际成本取决于 GPU 利用率与电价,建议以自家硬件实测 pages/s(官方提供 `benchmark_reproduction` 复现文档)折算。

---

## 7. 代码结构走读

### 7.1 仓库布局

```
MiniCPM-OCR/
├── README.md / README_zh.md      # 主文档(含评测表、权重入口)
├── AGENTS.md                     # 面向编码 Agent 的仓库说明
├── pyproject.toml
├── docs/                         # 45 篇中英文档(部署×4后端 / 微调 / API / FAQ / SKILL / 复现)
├── sdk/                          # PyPI 包 minicpm-ocr(解析前端)
│   ├── minicpmvocr/              # 核心库
│   ├── tests/                    # ~38 个 pytest 用例(OTSL 实体、跨页表、调度、HTTP 复用等)
│   ├── webdemo/                  # 参考实现:dispatcher/page_fleet/scoring_service(Jev 集成)
│   ├── webui/                    # 自带 Web 界面(含 KaTeX 渲染)
│   └── scripts/                  # llama.cpp/ollama 启动与评测脚本
├── scripts/
│   ├── install.sh                # feat-ocr vLLM 一键编译
│   └── minicpm-ocr-jev/          # Jev 评分服务/渲染器/多后端 yaml/评测脚本
└── assets/minicpm-ocr/           # 评测图 + benchmark-data.json(机器可读基准数据)
```

### 7.2 SDK 分层架构

| 模块 | 职责 | 二次开发价值 |
|---|---|---|
| `cli.py` | 子命令:`parse / run / parse-layout / prepare / infer / show-config / list-backends` | 可编程入口,`run` 支持断点续跑(`run_tag`) |
| `pipeline/` | 页面级编排:`staged/overlapped`(分页策略)、`upright`(方向矫正)、`rm_client`(**Jev 评分客户端**)、`_blocks`(切块) | 多进程/并发调度逻辑可直接复用 |
| `layouts/` | 版面 provider 三选一:`ppdoclayout3_paddlex / _torch / _server` | **可插拔**:可自研版面模型接入 |
| `backends/` | 推理后端抽象 + `dialects.py` 协议方言(vllm/llamacpp/openai/ollama) | **可插拔**:新增推理引擎只需实现协议 |
| `postprocess/` | `otsl→HTML`、`latex_repair`(公式修复)、`crosspage`(跨页表合并)、`markdown` 组装 | 独立工具函数,可单独取用 |
| `prompts.py` | 20+ 区域类型的提示词/token 预算/输出格式 + 外部 YAML 覆盖机制 | 提示词工程主入口 |

### 7.3 关键扩展点小结

- **换版面模型**:实现 layout provider 接口即可(已有 Paddle/Torch/HTTP 服务三种参考实现)。
- **换识别模型**:`openai.yaml` 后端可对接任何 OpenAI 兼容服务——意味着可以拿 MiniCPM-OCR 的流水线去跑自家微调模型做 A/B。
- **定制输出**:prompt_map YAML + markdown_assembly 配置,不动源码即可改字段、改格式、忽略指定元素。
- **质量门控**:`rm_client` + `scoring_service`(webdemo)是"解析→评分→分发复核"的完整参考实现,Docker 化 Jev 服务提供 4 个 HTTP 端点。
- 工程质量:类型标注完整(`py.typed`)、测试覆盖面合理、双语文档齐全,SDK 单独发版(语义化版本),适合作为依赖引入而非 fork。

---

## 8. 商用许可分析

**Apache License 2.0,且明确覆盖模型权重**——这在 OCR 开源方案中属于最宽松梯队。允许:商用、修改、微调、再分发、闭源集成;内置专利授权条款;义务仅为保留 LICENSE/NOTICE 与标注修改。贵方需注意的边界:

| 检查项 | 结论 |
|---|---|
| 权重许可 | Apache 2.0,无营收/用户数门槛,无地域排除 |
| 依赖链许可 | PaddlePaddle/PP-DocLayoutV3(Apache 2.0)、llama.cpp(MIT)、vLLM(Apache 2.0)——均无传染性问题 |
| 商标 | "MiniCPM" 名称与品牌不受许可约束,产品对外宣传避免暗示官方背书 |
| 训练数据 | 未披露,Apache 2.0 不担保;高合规场景(医疗/金融)按公司数据合规流程评估 |
| 竞品对照 | MinerU 权重附自定义条款(>1 亿 MAU 或月营收 2000 万美元需商业授权)、HunyuanOCR 社区许可排除欧盟/英国/韩国、Surya/Marker 权重 OpenRAIL(营收 <500 万美元免费)、GOT-OCR 2.0 许可口径存在争议——**MiniCPM-OCR 与 GLM-OCR(MIT)、PaddleOCR(Apache)是当前仅有的"零顾虑"选项** |

---

## 9. 竞品横向对比与选型建议

### 9.1 全景对比(2026-10 开源方案)

| 方案 | 参数量 | 架构路线 | 许可 | 显存下限(估) | 特点 |
|---|---|---|---|---|---|
| **MiniCPM-OCR 1.0 + Jev** | 1.3B + 2B | 版面优先 + 置信度判别 | Apache 2.0 | 24 GB(标准)/ 4 GB(GGUF) | 质量速度双优(自报)、唯一自带质量判别 |
| PaddleOCR-VL-1.6 | 0.9B | 版面优先 | Apache 2.0 | ~4 GB | Real5 官方榜现役第一(93.19),生态成熟、PP 全家桶 |
| GLM-OCR | 0.9B | 端到端 | MIT | ~3 GB | 1.4 GB 即可跑,支持 schema 引导 JSON,Ollama 可部署 |
| MinerU2.5-Pro | 1.2B | 版面优先 | Apache 2.0(Pro 版) | ~4 GB | 工程生态最全(80k star),多格式输出 |
| Xiaomi-OCR-0 | 0.8B | 专用 VLM | — | — | Real5 92.73,质量接近但吞吐较低 |
| DeepSeek-OCR-2 | 3B·MoE | 端到端 | Apache/MIT(口径不一) | ~6 GB | 单页成本导向,视觉 token 极省 |
| dots.ocr | 3B | 端到端 | MIT | ~8 GB | 图表→SVG、多语种强 |
| Unlimited-OCR | 3B·A0.5B | 端到端(RSWA) | MIT | 8 GB(厂商标注) | 40+ 页长文档单次通过 |
| GOT-OCR 2.0 | 580M | 端到端 | 存争议 | <3 GB | 老牌轻量统一 OCR |
| HunyuanOCR-1.5 | 1B | 端到端 | 自定义(排 EU/UK/韩) | — | 331 语种 |

### 9.2 选型建议(结合贵方场景)

- **主方案**:MiniCPM-OCR 1.0 值得作为首选试点——中英双语 + 低质扫描鲁棒性 + 吞吐 + Apache 2.0 + Jev 质量门控的组合,与"本地私有化 + 结构化提取 + RAG"的需求画像几乎完全重合。
- **对照方案**:PaddleOCR-VL-1.6(官方榜在册、可交叉验证精度)和 GLM-OCR(MIT、3GB 显存、端侧友好)作为 A/B 基线,三方在同一批业务样本上跑字段级准确率。
- **长文档场景**(百页连续合同/报告):Unlimited-OCR 的多页单次通过机制值得补充测试;MiniCPM-OCR 走 SDK 逐页流水线 + 跨页表合并(crosspage)亦可覆盖,但需要实测验证。
- **不建议**为贵方场景引入:许可有地域/营收条款的方案(HunyuanOCR、Marker/Surya 权重),减少合规审计成本。

---

## 10. 二次开发方向建议

### 10.1 方向一:文档结构化提取(票据/表单 → JSON)

- **短路径**:KIE prompt 直出 JSON(3.3 节),适合字段少、版式相对固定的单据;配合 Jev 对识别区域评分,高分区自动入库、低分区进人工复核,官方免检曲线显示可在保持准确率的前提下大幅降低复核量。
- **工程化建议**:
  1. 用 `minicpmvocr parse` 全量解析留档,再对目标区域二次 KIE,兼顾溯源与精度;
  2. 阈值校准按官方三步法:采样标注 → 多阈值统计"自动通过率 × 通过准确率" → 按业务容错线定阈值,**换文档分布后重新校准**;
  3. JSON 解析加容错(缺字段 `###`、markdown 围栏剥离),关键字段(金额/日期)建议双通道校验(规则 + 模型)。
- **风险提示**:Jev 打分以"区域"为单位,若下游字段粒度小于区域(单个金额),需确认区域边界与字段对齐;分数是排序信号而非概率,直接当置信度用会误判。

### 10.2 方向二:RAG 文档问答

- MiniCPM-OCR 的输出天然对齐 RAG 需求:标题层级 Markdown + HTML 表格 + LaTeX 公式 + 阅读顺序,解析质量决定检索上限。
- 推荐管线:`SDK 批量解析 → Jev 分数门控(低分块重解析/剔除/标记) → 结构感知分块(按标题切、表格整体成 chunk、表格序列化为文本描述双份索引) → 向量库`。
- 仓库内 `crosspage.py`(跨页表合并)、`latex_repair.py`(公式修复)可直接复用;`benchmark-data.json` 同目录的工程实践(webdemo 的 `page_fleet` 批量调度)适合作为生产编排参考。
- 相比通用 VLM 方案,该管线优势在**幻觉抑制**:版面优先架构每次只识别小裁片,幻觉面小;叠加 Jev 门控后,进入知识库的脏文本比例进一步可控。

### 10.3 方向三:微调自有模型

- **1.0 解析模型微调**:LLaMA-Factory(tsjyma fork,commit `38fa4bc`)与 ms-swift 双路径均有官方教程。关键配置:全参 SFT 训练视觉编码器 + 语言模型、**冻结多模态投影层**、开启 4× 视觉 token 压缩;数据为 sharegpt 格式 JSONL(`<image>\nText Recognition:` → 标注文本)。1.3B 全参 + DeepSpeed ZeRO-2 在 24 GB 单卡量级可训(仓库附 `ds_zero2.json` 配置,建议先小样本试跑),LoRA 则门槛更低。
- **Jev 微调**:ms-swift 教程覆盖二分类头配置,需要"区域原图 + 候选文本 + 渲染图 + 人工正误标签"四元组;适合把判别器对齐到贵方特有的文档类型与错误分布。
- **微调目标建议**:优先用 500–2000 张自有标注样本做"垂直版式 + 专有名词字典"适配(行业术语、印章体、非中英语种),通常比追基准分数收益更大;训练前先跑零样本 baseline,确认错误集中点再决定微调范围。

### 10.4 其他可行方向

- **多引擎 + Jev 择优**:已有 PaddleOCR/GLM-OCR 产能可直接叠加 Jev(`score_best_batch`)做免改造的质量增强,再逐步迁移主解析器。
- **国产芯片/信创**:FlagOS 多芯片适配文档(Torch-FL)提供 BF16 版本下载,信创环境可关注。
- **服务化封装**:webui/webdemo 提供完整前后端参考(GPU worker 池、任务分发、评分服务),可裁剪为内部文档处理平台;Jev 已有官方 Docker 镜像接口。

---

## 11. 风险清单与落地路线图

### 11.1 风险清单

| 风险 | 等级 | 缓解措施 |
|---|---|---|
| 项目极新(发布 2 天),API/依赖版本未冻结(文档含 `xxx` 占位) | 高 | 锁定 commit 与 SDK 版本;封装部署脚本;关注 release notes |
| 基准成绩自报,无独立复现;Real5 官方榜未收录 | 高 | POC 用自有样本做字段级评测,不依赖官方分数决策 |
| vLLM 需 feat-ocr 源码编译 + CUDA 13 工具链,运维摩擦大 | 中 | 固定 Docker 镜像;或先用 Transformers/llama.cpp 路径绕开编译 |
| 语种仅承诺中英;KIE 无 schema 约束;Jev 阈值需业务校准 | 中 | 按第 10 节流程校准;关键字段双通道校验 |
| 上游迭代快,DSpark 主/草稿模型必须同发布版本配套 | 低 | 下载时校验 `release_manifest.json` 的 sha256 |

### 11.2 建议落地路线图

| 阶段 | 周期 | 动作 | 产出 |
|---|---|---|---|
| P0 可行性 | 第 1 周 | 免费在线 Demo/云 API 投喂 100–200 张真实业务样本(含最差扫描件);与现役方案逐字段对比 | 零成本判断"值不值得继续" |
| P1 私有化 POC | 第 2–3 周 | 单卡 24/32 GB 部署标准 vLLM 路径;SDK 全流水线打通;Jev 阈值首轮校准 | 实测 pages/s、字段准确率、免检比例 |
| P2 竖井验证 | 第 4–6 周 | 结构化提取 + RAG 摄入两条业务线闭环;Docker 化;与 PaddleOCR-VL-1.6/GLM-OCR 三方横评 | 选型终审报告 |
| P3 定制深化 | 第 2 月起 | 视 P1/P2 结果决定:prompt 定制 → 微调(LoRA 起步)→ 生产扩容 | 垂直场景增强模型 |

---

## 附录 A:参考链接

| 资源 | 地址 |
|---|---|
| GitHub 仓库 | https://github.com/OpenBMB/MiniCPM-OCR |
| 主模型权重 | https://huggingface.co/openbmb/MiniCPM-OCR-1.0(ModelScope 同名) |
| DSpark 草稿头 | https://huggingface.co/openbmb/MiniCPM-OCR-1.0-DSpark |
| Jev 权重 | https://huggingface.co/openbmb/MiniCPM-OCR-1.0-Jev |
| JevOCRBench 数据集 | https://huggingface.co/datasets/openbmb/JevOCRBench |
| 在线 Demo | https://platform.modelbest.cn/console/playground/document-parse |
| Real5-OmniDocBench 官方榜 | https://aistudio.baidu.com/paddleocr/benchmark |
| 本报告仓库走读基线 | commit `b33b474`(2026-10-28 23:06 +0800) |

> 注:本报告第 4、6、9 节中标注"估"的数值为基于官方门槛与硬件规格的推算,非官方实测;所有基准分数除特别说明外均为项目方自报口径。采购与立项决策前建议以 POC 实测数据为准。
