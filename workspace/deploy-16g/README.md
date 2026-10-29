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

## 0. 系统依赖(一次性,sudo)

前置:Ubuntu 22.04 类系统、磁盘 ≥15 GB、内存 ≥16 GB。

```bash
# 基础工具链
sudo apt-get update
sudo apt-get install -y build-essential cmake git curl python3 python3-venv python3-pip

# NVIDIA 驱动 ≥535(能跑 nvidia-smi 即已就绪;新装后需重启)
nvidia-smi || { sudo apt-get install -y nvidia-driver-535; echo "== 重启系统后继续 =="; }

# CUDA Toolkit ≥12(编译 GGML_CUDA 需要 nvcc;Ubuntu 自带源版本偏旧,走 NVIDIA 官方源)
nvcc --version || {
  wget -q https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-keyring_1.1-1_all.deb
  sudo dpkg -i cuda-keyring_1.1-1_all.deb && sudo apt-get update
  sudo apt-get install -y cuda-toolkit-12-6
  echo 'export PATH=/usr/local/cuda/bin:$PATH' >> ~/.bashrc
}
export PATH=/usr/local/cuda/bin:$PATH   # 当前会话立即生效
```

## 0.5 conda Python 环境(推荐)

base 环境常带最新版 Python(如 3.13),而 Paddle 对 3.13 的轮子支持不全,安装易失败。建议建独立环境并在后续脚本(10/11/12/30 号)执行期间**保持激活**——Python 类脚本用它建 venv,编译用它找 nvcc:

```bash
conda create -n py312 python=3.12 -y
conda activate py312

# 仅当 00/01 号提示缺 nvcc 或 CUDA <12.8 时,给本环境装 CUDA Toolkit(RTX 50 系需 ≥12.8):
conda install -c nvidia cuda-toolkit=12.9 -y   # 建议 12.9+:对宿主 g++ 15 兼容更好
```

环境级依赖检查(激活后运行):

```bash
bash 01_check_python_env.sh   # conda env / python 版本 / pip / venv / 当前环境 nvcc / 编译工具
```

## 快速开始

两条路线:

- **最小路径(仅 1.0 解析,不部署 Jev)**:`00 → 10 → 11(SKIP_JEV=true) → 20 → 30 → 50`
- **完整路径(1.0 + Jev 质检)**:在最小路径基础上,`11` 不带 SKIP_JEV,并补 `12 → 22 → 21 → 23`,解析时 `JEV_ENABLED=true`

```bash
cd <仓库根>/workspace/deploy-16g
cp env.16g.example.sh env.local.sh   # 可选:改 HF_ENDPOINT 等;不建则用内置 16G 默认值

# 1) 体检(系统级 + Python 环境级;conda 环境需先激活)
bash 00_check_gpu.sh                 # 预期:汇总行"未过 0 项";含 GPU/驱动/磁盘/工具链/CUDA(nvcc)/HF 网络连通性
bash 01_check_python_env.sh          # 预期:"未过 0 项";conda env/python(推荐 3.12)/pip/venv/当前环境 nvcc

# 2) 编译 llama.cpp(数分钟;4060Ti/4090 可 LLAMA_CUDA_ARCH=89 加速,RTX 5080/5090 为 120,需 nvcc ≥12.8)
LLAMA_CUDA_ARCH=120 bash 10_build_llamacpp.sh   # 预期:产出 build/bin/llama-server
#    注:ARCH 须在首次配置前指定;已编译过想换架构:rm -rf ../llama.cpp/build 后重跑

# 3) 下载权重(最小路径跳过 Jev,省 4–5 GB)
SKIP_JEV=true bash 11_download_weights.sh      # 预期:gguf/ 下两个 .gguf 文件

# 4) 起 1.0 引擎
bash 20_start_ocr_engine.sh          # 预期:"就绪: http://127.0.0.1:18601/health";nvidia-smi 约 4–6 GB

# 5) SDK 环境(版面检测默认 CPU,不占显存)
bash 30_setup_sdk_env.sh             # 预期:"SDK ok"

# 6) 冒烟测试(内部自动调 40 号脚本跑一张仓库自带示例图)
bash 50_smoke_test.sh                # 预期:健康检查 ✓ + 显存快照 + 解析产物列表

# 7) 解析自己的文件
bash 40_parse.sh /path/to/doc.pdf ./out
```

完整路径补充(在最小路径的步骤 3–4 之间插入):

```bash
bash 11_download_weights.sh          # 不带 SKIP_JEV,幂等:已下的 1.0 跳过,补下 Jev
bash 12_convert_jev_gguf.sh          # Jev 转 GGUF(首次约 10–20 分钟)
bash 22_setup_jev_render_env.sh      # 渲染环境(Chromium/Node/字体,较慢)
bash 21_start_jev_engine.sh
bash 23_start_jev_service.sh         # 预期:healthz 返回 "status": "ok"
JEV_ENABLED=true bash 40_parse.sh /path/to/doc.pdf ./out
```

停止全部服务:`bash 90_stop_all.sh`。服务类脚本的日志统一在 `../run/logs/`。

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
| `00_check_gpu.sh` | 环境体检:GPU/显存/驱动/磁盘/工具链/CUDA 工具链(nvcc,Blackwell 需 ≥12.8)/HF 网络连通性 |
| `01_check_python_env.sh` | Python 环境体检:conda env/python 版本(3.12 首选)/pip/venv/当前环境 nvcc/编译工具 |
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

- **10 号报 `unsupported GNU version! gcc versions later than ...`**:nvcc 拒绝过新的宿主 g++(如 15.x)。处理:在本环境 `conda install -c conda-forge gxx_linux-64=14`(为 nvcc 提供兼容宿主编译器),或改装 `cuda-toolkit=12.9/13.0`。
- **20 号启动报 `libcudart.so.12: cannot open shared object file`**:CUDA Toolkit 装在 conda 环境里时,先 `conda activate py312` 再起引擎;或 `export LD_LIBRARY_PATH=$CONDA_PREFIX/lib:$LD_LIBRARY_PATH`。
- **400/静默重试类问题**:llama.cpp 路径不涉及 vLLM 的 `--trust-request-mm-kwargs` 与 chat template 参数,GGUF 内嵌模板已关闭 thinking,无需额外设置。
- **首次解析卡在下载**:版面模型(约几百 MB)来自 Paddle 官方地址,网络受限时手动下载 `PP-DocLayoutV3_infer.tar` 解压后 `export OCR_LAYOUT_MODEL_DIR=/path/to/PP-DocLayoutV3_infer`。
- **解析挂死先看引擎日志**:`../run/logs/*.log`;再 `curl http://127.0.0.1:18601/health`。
- **DSpark 无效是正常的**:llama.cpp 路径不支持投机解码,`50_smoke_test.sh` 不做该检查。
- 上游脚本(`sdk/scripts/`、`scripts/minicpm-ocr-jev/`)与本包并存:本包不修改上游文件,`22/23` 号脚本直接调用上游入口(只读使用,符合协作规则)。
