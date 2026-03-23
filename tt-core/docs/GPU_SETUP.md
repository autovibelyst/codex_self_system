# GPU Setup for Ollama — TT-Production v14.0

Ollama runs on CPU by default. GPU acceleration dramatically improves inference speed.

## Requirements Check

```bash
# NVIDIA: verify driver is installed
nvidia-smi

# AMD: verify ROCm is installed
rocm-smi

# Check Docker GPU support
docker run --rm --gpus all nvidia/cuda:12.0-base-ubuntu22.04 nvidia-smi
```

## NVIDIA GPU Setup

### Step 1: Install NVIDIA Container Toolkit

```bash
# Ubuntu/Debian
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | \
  sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg

curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
  sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
  sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

sudo apt-get update && sudo apt-get install -y nvidia-container-toolkit
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker
```

### Step 2: Enable GPU in docker-compose.yml

In `tt-core/compose/tt-core/docker-compose.yml`, find the `ollama` service and
uncomment the GPU section:

```yaml
  ollama:
    profiles: ["ollama", "openwebui"]
    # ... existing config ...
    deploy:
      resources:
        # Remove the non-GPU limits block and use this instead:
        reservations:
          devices:
            - driver: nvidia
              count: all          # Use 'all' or a specific number: 1, 2
              capabilities: [gpu]
```

### Step 3: Verify GPU is available to Ollama

```bash
docker exec tt-core-ollama nvidia-smi
```

### Step 4: Pull a model and test

```bash
# Pull a model (via Open WebUI or direct exec)
docker exec tt-core-ollama ollama pull llama3.2

# Test inference
docker exec tt-core-ollama ollama run llama3.2 "Hello, are you using GPU?"
```

## AMD GPU Setup (ROCm)

AMD GPU support requires the ROCm-enabled Ollama image:

```yaml
  ollama:
    profiles: ["ollama", "openwebui"]
    image: ollama/ollama:0.6.5-rocm     # ROCm variant
    devices:
      - /dev/kfd:/dev/kfd
      - /dev/dri:/dev/dri
    group_add:
      - video
      - render
```

Verify ROCm: `docker exec tt-core-ollama ollama run llama3.2 "test"`

## Memory Requirements by Model

| Model         | VRAM Required | CPU RAM (no GPU) |
|---------------|--------------|-----------------|
| llama3.2:3b   | 3 GB         | 4 GB            |
| llama3.2:8b   | 8 GB         | 10 GB           |
| llama3.1:70b  | 40 GB        | Not recommended |
| gemma2:9b     | 9 GB         | 12 GB           |
| phi3:mini     | 2.5 GB       | 3 GB            |

## Troubleshooting

**GPU not detected:**
```bash
# Check nvidia-ctk is configured
sudo nvidia-ctk runtime configure --runtime=docker --dry-run

# Restart Docker after toolkit install
sudo systemctl restart docker
```

**Out of VRAM:**
- Use a smaller model (`ollama pull phi3:mini`)
- Or increase Ollama memory limit in docker-compose.yml (`memory: 16g`)

**Permission denied on /dev/dri (AMD):**
```bash
sudo usermod -aG video,render $USER
# Re-login for group changes to take effect
```

---

## AMD GPU Setup (ROCm)

### Requirements
- AMD GPU with ROCm support (RX 6000 series or newer recommended)
- Host OS: Ubuntu 22.04+ (ROCm 5.7+)
- ROCm installed: https://rocm.docs.amd.com/en/latest/deploy/linux/quick_start.html

### Step 1: Install ROCm on Host

```bash
# Ubuntu 22.04
wget https://repo.radeon.com/amdgpu-install/6.1.2/ubuntu/jammy/amdgpu-install_6.1.60102-1_all.deb
sudo dpkg -i amdgpu-install_6.1.60102-1_all.deb
sudo amdgpu-install --usecase=rocm
sudo usermod -a -G render,video $USER
# Reboot required
```

### Step 2: Enable AMD GPU in docker-compose.yml

Find the `ollama` service and replace the default memory limits with:

```yaml
  ollama:
    deploy:
      resources:
        reservations:
          devices:
            - driver: amdgpu
              count: all
              capabilities: [gpu, compute]
    environment:
      TZ: ${TT_TZ}
      # For RX 7000 series (RDNA3):
      HSA_OVERRIDE_GFX_VERSION: "11.0.0"
      # For RX 6000 series (RDNA2):
      # HSA_OVERRIDE_GFX_VERSION: "10.3.0"
      # For RX 580/590 Polaris:
      # ROC_ENABLE_PRE_VEGA: "1"
```

### Step 3: Verify AMD GPU is available to Ollama

```bash
docker exec tt-core-ollama rocm-smi
docker exec tt-core-ollama ollama run llama3.2 "Hello"
```

### GFX Version Reference

| GPU Series | HSA_OVERRIDE_GFX_VERSION |
|-----------|--------------------------|
| RX 7900/7800/7700 (RDNA3) | 11.0.0 |
| RX 6900/6800/6700/6600 (RDNA2) | 10.3.0 |
| RX 5700/5600/5500 (RDNA1) | 10.1.0 |
| RX 580/590 (Polaris) | use ROC_ENABLE_PRE_VEGA=1 |
