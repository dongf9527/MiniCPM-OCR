#!/usr/bin/env bash
# deploy-16g 环境变量模板
# 用法: cp env.16g.example.sh env.local.sh && 按需修改
#       所有脚本启动时自动 source env.local.sh;不创建则使用下方各默认值。
# 默认值即 16G 单卡(无并发)推荐配置。

# ---- 路径(默认自动推导,一般无需修改)----
# WORKSPACE_DIR     推导自脚本位置,即 workspace/
# LLAMACPP_DIR      默认 $WORKSPACE_DIR/llama.cpp
# ASSETS: GGUF 与 Jev 权重默认落 $WORKSPACE_DIR/gguf 与 $WORKSPACE_DIR/jev-hf

# ---- 下载 ----
# HF 镜像加速(国内可改 https://hf-mirror.com)
# export HF_ENDPOINT="https://hf-mirror.com"

# ---- llama.cpp 编译(10 号脚本)----
# 指定 CUDA 架构可加速编译:86(A30/A40/3090) 89(4090) 120(5090);留空=编译全部
# export LLAMA_CUDA_ARCH=""

# ---- 1.0 解析引擎(20 号脚本)----
# export OCR_HOST="127.0.0.1"
# export OCR_PORT="18601"
# export OCR_CTX="8192"        # 上下文;显存富余可升 16384
# export OCR_NGL="999"         # 全部层上卡;0=纯 CPU

# ---- Jev 引擎(21 号脚本)----
# 官方示例 ctx=32768;与 1.0 共卡 16G 时建议 16384,OOM 再降 8192
# export JEV_PORT="18602"
# export JEV_CTX="16384"
# export JEV_NGL="999"

# ---- Jev 评分服务(23 号脚本)----
# export JEV_SERVICE_PORT="18500"
# 渲染环境 venv 位置(22 号脚本创建)
# export JEV_RENDER_VENV=""    # 默认 $WORKSPACE_DIR/venv-render
# 渲染并发浏览器数(无并发需求保持 1)
# export RM_RENDER_BROWSERS="1"

# ---- SDK / 解析(30、40 号脚本)----
# 版面检测设备:cpu(默认,不占显存)或 cuda:0(需 30 号脚本以 GPU 模式安装 paddle)
# export LAYOUT_DEVICE="cpu"
# 是否在解析时启用 Jev 评分门控:40 号脚本读取
# export JEV_ENABLED="false"
# export SDK_VENV=""           # 默认 $WORKSPACE_DIR/venv-sdk
# 解析模型名(llama-server 对外服务名,保持默认即可)
# export OCR_MODEL_NAME="minicpm-ocr"

# ---- 渲染/转换环境慢网镜像(可选)----
# export PIP_INDEX_URL="https://pypi.tuna.tsinghua.edu.cn/simple"
# export PLAYWRIGHT_DOWNLOAD_HOST="https://npmmirror.com/mirrors/playwright"
