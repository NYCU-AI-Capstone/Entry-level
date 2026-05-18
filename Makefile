.PHONY: install install-dev test \
	submodules submodules-pull \
	build-isaaclab launch-isaaclab \
	launch-isaaclab-glowsai-4090 launch-isaaclab-glowsai-l40s \
	install-isaaclab-native launch-isaaclab-native datagen-native \
	check-isaaclab-gpu

# ---- Config ------------------------------------------------------------------
IMAGE          ?= leisaac-isaaclab:latest
DOCKERFILE     ?= Dockerfile
GPU            ?= all
CONTAINER_NAME ?= isaaclab

# ---- Shared shell snippets ---------------------------------------------------
# Pick first existing NVIDIA Vulkan ICD and export VK_ICD_FILENAMES.
define select_vulkan_icd
unset VK_ICD_FILENAMES; \
for icd in \
	/usr/share/vulkan/icd.d/nvidia_icd.json \
	/etc/vulkan/icd.d/nvidia_icd.json; do \
	if [ -f "$$icd" ]; then \
		export VK_ICD_FILENAMES="$$icd"; \
		echo "Using Vulkan ICD: $$VK_ICD_FILENAMES"; \
		break; \
	fi; \
done; \
if [ -z "$${VK_ICD_FILENAMES:-}" ]; then \
	echo "WARNING: No NVIDIA Vulkan ICD found."; \
	echo "Check nvidia-container-toolkit / driver installation."; \
fi
endef

# Verify required GL/X/Vulkan libs are visible to ldconfig.
define require_runtime_libs
for lib in libGLU.so.1 libXt.so.6 libX11.so.6 libvulkan.so.1; do \
	if ! ldconfig -p | grep -q "$$lib"; then \
		echo "Missing $$lib in image." >&2; \
		exit 1; \
	fi; \
done
endef

# ---- Submodules --------------------------------------------------------------
submodules:
	git submodule update --init --recursive

submodules-pull:
	git submodule update --remote --recursive

# ---- Python env --------------------------------------------------------------
install: submodules
	uv sync

install-dev: submodules
	uv sync --extra dev

test:
	PYTEST_DISABLE_PLUGIN_AUTOLOAD=1 uv run --extra dev pytest \
		tests/test_repo_layout.py \
		tests/test_external_task_resolver.py

# ---- Docker image ------------------------------------------------------------
build-isaaclab: submodules
	docker build -f $(DOCKERFILE) -t $(IMAGE) .

# ---- Launch: default ---------------------------------------------------------
launch-isaaclab: build-isaaclab
	@set -e; \
	xhost +local:root >/dev/null || true; \
	trap 'xhost -local:root >/dev/null || true' EXIT; \
	docker run --rm -it \
		--name $(CONTAINER_NAME) \
		--gpus '"device=$(GPU)"' \
		--net=host \
		--ipc=host \
		--ulimit memlock=-1 \
		--ulimit stack=67108864 \
		-v $(shell pwd):/workspace/aicapstone \
		-v /workspace/aicapstone/.venv \
		-v /tmp/.X11-unix:/tmp/.X11-unix:rw \
		-v /usr/share/vulkan/icd.d:/usr/share/vulkan/icd.d:ro \
		-v /etc/vulkan/icd.d:/etc/vulkan/icd.d:ro \
		-e DISPLAY=$$DISPLAY \
		-e OMNI_KIT_ACCEPT_EULA=Y \
		-e PRIVACY_CONSENT=Y \
		-e QT_X11_NO_MITSHM=1 \
		-e NVIDIA_VISIBLE_DEVICES=$(GPU) \
		-e NVIDIA_DRIVER_CAPABILITIES=graphics,display,utility,compute \
		$(IMAGE) \
		bash -lc '\
			set -e; \
			echo "== GPU check =="; nvidia-smi || true; \
			echo "== Vulkan ICD candidates =="; \
			ls -l /usr/share/vulkan/icd.d /etc/vulkan/icd.d 2>/dev/null || true; \
			$(select_vulkan_icd); \
			$(require_runtime_libs); \
			cd /workspace/aicapstone; \
			exec /bin/bash \
		'

# ---- Launch: GlowsAI RTX 4090 (VNC display :1) ------------------------------
launch-isaaclab-glowsai-4090: build-isaaclab
	@set -e; \
	docker run --rm -it \
		--name $(CONTAINER_NAME)-glowsai-4090 \
		--gpus '"device=0"' \
		--net=host \
		--ipc=host \
		--ulimit memlock=-1 \
		--ulimit stack=67108864 \
		--shm-size=16g \
		-v $(shell pwd):/workspace/aicapstone \
		-v /workspace/aicapstone/.venv \
		-v /home/glows/.Xauthority:/root/.Xauthority:ro \
		-v /tmp/.X11-unix:/tmp/.X11-unix:rw \
		-v /opt/VirtualGL:/opt/VirtualGL:ro \
		-v /usr/share/vulkan/icd.d:/usr/share/vulkan/icd.d:ro \
		-v /etc/vulkan/icd.d:/etc/vulkan/icd.d:ro \
		-e DISPLAY=:1 \
		-e USE_VNC=1 \
		-e OMNI_KIT_ACCEPT_EULA=Y \
		-e PRIVACY_CONSENT=Y \
		-e QT_X11_NO_MITSHM=1 \
		-e NVIDIA_VISIBLE_DEVICES=0 \
		-e NVIDIA_DRIVER_CAPABILITIES=graphics,display,utility,compute \
		$(IMAGE) \
		bash -lc '\
			set -e; \
			echo "=== GlowsAI RTX 4090 ==="; \
			echo "Display: $$DISPLAY"; \
			echo "== GPU check =="; nvidia-smi || true; \
			echo "== Vulkan ICD candidates =="; \
			ls -l /usr/share/vulkan/icd.d /etc/vulkan/icd.d 2>/dev/null || true; \
			$(select_vulkan_icd); \
			$(require_runtime_libs); \
			cd /workspace/aicapstone; \
			exec /bin/bash \
		'

# ---- Launch: GlowsAI L40S (VirtualGL + VNC display :1) -----------------------
launch-isaaclab-glowsai-l40s: build-isaaclab
	@set -e; \
	docker run --rm -it \
		--name $(CONTAINER_NAME)-glowsai-l40s \
		--gpus '"device=0"' \
		--net=host \
		--ipc=host \
		--ulimit memlock=-1 \
		--ulimit stack=67108864 \
		--shm-size=16g \
		-v $(shell pwd):/workspace/aicapstone \
		-v /workspace/aicapstone/.venv \
		-v /home/glows/.Xauthority:/root/.Xauthority:ro \
		-v /tmp/.X11-unix:/tmp/.X11-unix:rw \
		-v /opt/VirtualGL:/opt/VirtualGL:ro \
		-v /usr/share/vulkan/icd.d:/usr/share/vulkan/icd.d:ro \
		-v /etc/vulkan/icd.d:/etc/vulkan/icd.d:ro \
		-e DISPLAY=:1 \
		-e USE_VNC=1 \
		-e VGL_DISPLAY=egl0 \
		-e PATH=/opt/VirtualGL/bin:$$PATH \
		-e OMNI_KIT_ACCEPT_EULA=Y \
		-e PRIVACY_CONSENT=Y \
		-e QT_X11_NO_MITSHM=1 \
		-e NVIDIA_VISIBLE_DEVICES=0 \
		-e NVIDIA_DRIVER_CAPABILITIES=graphics,display,utility,compute \
		$(IMAGE) \
		bash -lc '\
			set -e; \
			echo "=== GlowsAI L40S ==="; \
			echo "Display: $$DISPLAY"; \
			echo "VGL_DISPLAY: $$VGL_DISPLAY"; \
			echo "== GPU check =="; nvidia-smi || true; \
			echo "== Vulkan ICD candidates =="; \
			ls -l /usr/share/vulkan/icd.d /etc/vulkan/icd.d 2>/dev/null || true; \
			$(select_vulkan_icd); \
			$(require_runtime_libs); \
			cd /workspace/aicapstone; \
			exec /bin/bash \
		'

# ---- Native install (no Docker; conda env on host) ---------------------------
# Mirrors the Dockerfile pip sequence into a host conda env so the simulator
# can run directly on machines where Docker isn't available.
NATIVE_CONDA_ENV ?= isaaclab-native

define activate_native_env
eval "$$(conda shell.bash hook)" && conda activate $(NATIVE_CONDA_ENV)
endef

install-isaaclab-native: submodules
	@set -e; \
	if ! command -v conda >/dev/null; then \
		echo "conda not found on PATH" >&2; exit 1; \
	fi; \
	eval "$$(conda shell.bash hook)"; \
	if ! conda env list | awk '{print $$1}' | grep -qx "$(NATIVE_CONDA_ENV)"; then \
		conda create -y -n $(NATIVE_CONDA_ENV) python=3.11; \
	fi; \
	conda activate $(NATIVE_CONDA_ENV); \
	export ACCEPT_EULA=Y OMNI_KIT_ACCEPT_EULA=YES PRIVACY_CONSENT=Y; \
	python -m pip install --upgrade pip; \
	python -m pip install -U torch==2.7.0 torchvision==0.22.0 \
		--index-url https://download.pytorch.org/whl/cu128; \
	python -m pip install --upgrade "isaacsim[all,extscache]==5.1.0" \
		--extra-index-url https://pypi.nvidia.com; \
	python -m pip install pip==23 setuptools==65 flatdict==4.0.0 \
		huggingface-hub==0.35.3 transformers==4.57.6; \
	python -m pip install --no-deps setuptools==65 wheel==0.45.1 toml==0.10.2 \
		packaging==23.0 poetry-core==2.2.1; \
	sed -i 's|-m pip install"|-m pip install --no-build-isolation"|' \
		dependencies/IsaacLab/isaaclab.sh; \
	(cd dependencies/IsaacLab && ./isaaclab.sh --install); \
	python -m pip install --no-deps numpy==1.26.0; \
	python -m pip install --upgrade setuptools==80.10.2 wheel==0.45.1 \
		cython==3.0.11 toml==0.10.2 packaging==24.2; \
	printf "numpy==1.26.0\n" > /tmp/sim-constraints.txt; \
	python -m pip install --use-deprecated=legacy-resolver --no-build-isolation \
		-c /tmp/sim-constraints.txt -e packages/simulator; \
	python -m pip install --no-deps numpy==1.26.0; \
	rm -f /tmp/sim-constraints.txt; \
	python -m pip install --upgrade pip==26.0.1; \
	python -m pip install --no-deps numpy==1.26.0; \
	echo; \
	echo "Native install complete. Activate via: conda activate $(NATIVE_CONDA_ENV)"

# ---- Native headless shell (no Docker, no display) ---------------------------
launch-isaaclab-native:
	@set -e; \
	$(activate_native_env); \
	unset DISPLAY; \
	export OMNI_KIT_ACCEPT_EULA=Y PRIVACY_CONSENT=Y; \
	export NVIDIA_DRIVER_CAPABILITIES=graphics,display,utility,compute; \
	$(select_vulkan_icd); \
	echo "== GPU check =="; nvidia-smi -L; \
	echo; \
	echo "Env: $(NATIVE_CONDA_ENV) (headless, no DISPLAY)"; \
	echo "Run datagen via:"; \
	echo "  python scripts/datagen/generate.py --task <TASK> --num_envs 1 \\"; \
	echo "      --device cuda --headless --enable_cameras --record \\"; \
	echo "      --use_lerobot_recorder --lerobot_dataset_repo_id \$$HF_USER/<repo> \\"; \
	echo "      --object_poses data/<demo>/object_poses.json"; \
	exec /bin/bash

# ---- Native datagen (no Docker, no display) ----------------------------------
# Forward extra args via DATAGEN_ARGS=, e.g.:
#   make datagen-native DATAGEN_ARGS='--task HCIS-CupStacking-SingleArm-v0 \
#       --num_envs 1 --device cuda --record --use_lerobot_recorder \
#       --lerobot_dataset_repo_id $$HF_USER/cup-stacking-sim-v0 \
#       --object_poses data/kitchen-object-poses/object_poses.json'
DATAGEN_ARGS ?=
datagen-native:
	@set -e; \
	$(activate_native_env); \
	unset DISPLAY; \
	export ACCEPT_EULA=Y OMNI_KIT_ACCEPT_EULA=YES PRIVACY_CONSENT=Y; \
	export NVIDIA_DRIVER_CAPABILITIES=graphics,display,utility,compute; \
	$(select_vulkan_icd); \
	python scripts/datagen/generate.py --headless --enable_cameras $(DATAGEN_ARGS)

# ---- GPU sanity check --------------------------------------------------------
check-isaaclab-gpu:
	@docker run --rm \
		--device nvidia.com/gpu=all \
		-e ACCEPT_EULA=Y \
		-e NVIDIA_VISIBLE_DEVICES=all \
		-e NVIDIA_DRIVER_CAPABILITIES=all \
		-e __GLX_VENDOR_LIBRARY_NAME=nvidia \
		$(IMAGE) \
		bash -lc '\
			set -e; \
			$(select_vulkan_icd); \
			if [ -z "$${VK_ICD_FILENAMES:-}" ]; then exit 1; fi; \
			nvidia-smi; \
			ldconfig -p | grep "libGLU.so.1"; \
			ldconfig -p | grep "libXt.so.6"; \
			python -c "import torch; print(\"torch cuda available:\", torch.cuda.is_available()); print(\"torch cuda device:\", torch.cuda.get_device_name(0))"; \
			ls -l /etc/vulkan/icd.d /usr/share/vulkan/icd.d 2>/dev/null || true; \
			vulkaninfo --summary; \
		'
