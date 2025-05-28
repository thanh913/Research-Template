# syntax=docker/dockerfile:1
FROM --platform=linux/arm64 nvcr.io/nvidia/pytorch:24.08-py3

################ 1. env ################
ENV DEBIAN_FRONTEND=noninteractive \
    HF_HUB_ENABLE_HF_TRANSFER=1 \
    MAX_JOBS=72 \
    VLLM_WORKER_MULTIPROC_METHOD=spawn \
    TORCH_CUDA_ARCH_LIST="90" \
    CUDAARCHS="90" \
    CMAKE_ARGS="-DCMAKE_CUDA_ARCHITECTURES=90" \
    CONDA_DIR=/opt/conda \
    PATH=/opt/conda/bin:$PATH

ARG APT_MIRROR=https://mirrors.tuna.tsinghua.edu.cn/ubuntu/
ARG PIP_MIRROR=https://mirrors.tuna.tsinghua.edu.cn/pypi/web/simple
ARG SGLANG_VER=0.4.6.post4
ARG USERNAME=researcher

############### 2. mirrors ##############
RUN sed -i.bak "s|http://.*.ubuntu.com/ubuntu/|${APT_MIRROR}|g" /etc/apt/sources.list && \
    pip config set global.index-url "${PIP_MIRROR}" && \
    pip config set global.extra-index-url "${PIP_MIRROR}" && \
    python -m pip install --upgrade pip

############### 3. system deps ##########
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential git ninja-build cmake pkg-config patchelf \
        curl wget ca-certificates tmux mosh htop nvtop aria2 \
        python3-venv libssl-dev libgoogle-perftools-dev \
        libjpeg-dev libpng-dev && \
    rm -rf /var/lib/apt/lists/*

############### 4. clean torch ##########
RUN pip uninstall -y torch torchvision torchaudio flash_attn apex \
                      transformer_engine megatron-core || true

############### 5. torch 2.6 + cu126 ####
RUN pip install -v --no-cache-dir \
        --extra-index-url https://download.pytorch.org/whl/cu126 \
        torch==2.6.0+cu126

RUN pip install -v --no-build-isolation --no-cache-dir --no-deps \
        git+https://github.com/pytorch/vision.git@v0.22.0

RUN pip install -v --no-cache-dir torchaudio==2.6.0      # CPU wheel

############### 6. core stack ###########
RUN pip install -v --no-cache-dir \
        vllm==0.8.5.post1 \
        "sglang[flashinfer,openai,cli]==${SGLANG_VER}" \
        tensordict==0.8.3 torchdata \
        "transformers[hf_xet]>=4.51.0" accelerate datasets peft hf-transfer \
        "numpy<2.0.0" pyarrow>=15 pandas ray[default] wandb dill ruff \
        fastapi[standard]>=0.115 optree>=0.13 pydantic>=2.9 grpcio>=1.62 \
        verl openai litellm tqdm psutil cloudpickle

###############################################################################
# 7. Flash-Attention (source) – capped at 16 parallel nvcc jobs
###############################################################################
ARG FLASH_JOBS=16
RUN git clone --depth 1 --branch v2.7.4.post1 https://github.com/Dao-AILab/flash-attention.git && \
    cd flash-attention && \
    MAX_JOBS=${FLASH_JOBS} pip install -v --no-build-isolation --no-cache-dir . && \
    cd .. && rm -rf flash-attention

###############################################################################
# 8. Apex – cross-compile for sm_80, 8 parallel jobs
###############################################################################
ARG APEX_JOBS=32
ARG APEX_CUDA_ARCH="8.0"
RUN git clone --depth 1 https://github.com/NVIDIA/apex.git && \
    cd apex && \
    MAX_JOBS=${APEX_JOBS} \
    TORCH_CUDA_ARCH_LIST="${APEX_CUDA_ARCH}" \
    pip install -v --no-cache-dir --no-build-isolation \
        --config-settings="--build-option=--cpp_ext" \
        --config-settings="--build-option=--cuda_ext" . && \
    cd .. && rm -rf apex

############### 9. TE & Megatron #########
RUN pip install -v --no-deps --no-cache-dir \
        git+https://github.com/NVIDIA/TransformerEngine.git@v2.3 && \
    pip install -v --no-deps --no-cache-dir \
        git+https://github.com/NVIDIA/Megatron-LM.git@core_v0.12.0

############### 10. vLLM #################
RUN git clone --depth 1 --branch v0.8.5 https://github.com/vllm-project/vllm.git && \
    cd vllm && \
    pip install -v --no-cache-dir . && \
    cd .. && rm -rf vllm

############### 11. miniconda + pipx #####
RUN wget -qO /tmp/conda.sh https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-aarch64.sh && \
    bash /tmp/conda.sh -b -p $CONDA_DIR && rm /tmp/conda.sh && \
    conda config --set solver libmamba && conda config --set auto_activate_base false && \
    python -m pip install --no-cache-dir pipx && \
    pipx ensurepath && \
    pipx install gpustat && \
    pipx install ntfy-wrapper

############### 12. final ###############
RUN useradd -m -s /bin/bash ${USERNAME}
WORKDIR /workspace
USER ${USERNAME}
CMD ["bash"]
