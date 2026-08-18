## Day 18 Lakehouse Lab — student UX
## Two paths: lightweight (default, pure Python) and Spark (Docker, optional).

VENV       := .venv
export PYTHONUTF8 := 1

ifeq ($(OS),Windows_NT)
    SHELL       := powershell.exe
    .SHELLFLAGS := -NoProfile -Command
    VENV_BIN    := Scripts
    PYTHON      := python
    EXE         := .exe
else
    VENV_BIN    := bin
    PYTHON      := python3
    EXE         :=
endif

PY         := $(VENV)/$(VENV_BIN)/python$(EXE)
PIP        := $(VENV)/$(VENV_BIN)/pip$(EXE)
JUPYTER    := $(VENV)/$(VENV_BIN)/jupyter$(EXE)
JUPYTEXT   := $(VENV)/$(VENV_BIN)/jupytext$(EXE)
PYTEST     := $(VENV)/$(VENV_BIN)/pytest$(EXE)
COMPOSE    := docker compose -f docker/docker-compose.yml

.DEFAULT_GOAL := help

help: ## Show this help
	@$(PYTHON) -c "import re; [print(f'  \033[36m{m.group(1):<14}\033[0m {m.group(2)}') for line in open('Makefile', encoding='utf-8') if (m := re.match(r'^([a-zA-Z_-]+):.*?##\s*(.*)', line))]"

# ─────────────────────────────────────────────────────────────
# Lightweight path (default) — pure Python, no Docker, no JVM
# ─────────────────────────────────────────────────────────────

setup: ## [lite] Create venv + install deps (~180 MB, ~20s with pip / ~4s with uv)
ifeq ($(OS),Windows_NT)
	@if (Get-Command uv -ErrorAction SilentlyContinue) { if (-not (Test-Path $(VENV))) { uv venv $(VENV) --python python }; uv pip install --python $(PY) -r requirements.txt } else { if (-not (Test-Path $(VENV))) { $(PYTHON) -m venv $(VENV) }; $(PIP) install -q -r requirements.txt }
	@$(PY) -c "import sys; sys.exit(0 if (3,10)<=sys.version_info[:2]<(3,13) else 1)"
	-@$(JUPYTEXT) --to notebook --update notebooks/*.py 2>$$null
	@echo " "
	@echo "Setup complete. Run make smoke then make lab."
else
	@command -v uv >/dev/null 2>&1 && uv venv $(VENV) --python '>=3.10,<3.13' || $(PYTHON) -m venv $(VENV)
	@$(PY) -c 'import sys; raise SystemExit(0 if (3,10)<=sys.version_info[:2]<(3,13) else 1)' \
	  || { echo "ERROR: need Python 3.10-3.12. Install 'uv' (auto-fetches one) or run: $(PYTHON) -m venv $(VENV)"; exit 1; }
	@command -v uv >/dev/null 2>&1 && uv pip install --python $(PY) -r requirements.txt \
	  || $(PIP) install -q -r requirements.txt
	-@$(JUPYTEXT) --to notebook --update notebooks/*.py 2>/dev/null
	@echo " "
	@echo "Setup complete. Run make smoke then make lab."
endif

smoke: ## [lite] ~15-second end-to-end smoke test (Delta + Iceberg + vectors)
	@$(PY) scripts/verify_lite.py

test: ## [lite] Run the pytest suite the instructor grades against
	@$(PYTEST) -q

lab: ## [lite] Open Jupyter Lab on http://localhost:8888
ifeq ($(OS),Windows_NT)
	-@$(JUPYTEXT) --to notebook --update notebooks/*.py 2>$$null
	@$(JUPYTER) lab --notebook-dir=notebooks --ServerApp.token='' --no-browser
else
	-@$(JUPYTEXT) --to notebook --update notebooks/*.py 2>/dev/null || true
	@$(JUPYTER) lab --notebook-dir=notebooks --ServerApp.token='' --no-browser
endif

data: ## [lite] Generate 200K-row Bronze sample for NB4
	@$(PY) scripts/generate_data_lite.py

data-ai: ## [lite] Generate multimodal + agent-trajectory sample for NB7/NB8
	@$(PY) scripts/generate_ai_data.py

run-all: ## [lite] Execute every notebook headlessly (what CI does)
	@$(PY) scripts/run_all.py

simulate: ## [lite] Abuse the lab the way students do (12 scenarios; SIM_FAST=1 to skip venv builds)
	@$(PY) tests/simulate_students.py

clean: ## [lite] Wipe venv + lakehouse data
ifeq ($(OS),Windows_NT)
	-@Remove-Item -Recurse -Force $(VENV), _lakehouse, notebooks/.ipynb_checkpoints, .pytest_cache -ErrorAction SilentlyContinue
else
	rm -rf $(VENV) _lakehouse notebooks/.ipynb_checkpoints .pytest_cache
endif

# ─────────────────────────────────────────────────────────────
# Spark on Apple `container` (optional) — macOS 15+, Apple silicon
# Same 3-service stack as the compose path, driven by `container run`,
# because Apple's runtime has no compose plugin and no Docker socket.
# ─────────────────────────────────────────────────────────────

AC := scripts/apple_container.sh

apple-up: ## [apple] Start MinIO + buckets + Spark/Jupyter via Apple `container`
	@$(AC) up

apple-smoke: ## [apple] Run scripts/verify.py in the Spark container
	@$(AC) smoke

apple-data: ## [apple] Generate the 1M-row Bronze table via Spark
	@$(AC) data

apple-status: ## [apple] Show containers + MinIO's injected IP
	@$(AC) status

apple-down: ## [apple] Stop and remove containers (MinIO data kept)
	@$(AC) down

apple-clean: ## [apple] Same as apple-down, plus delete _minio-data/
	@$(AC) clean

# ─────────────────────────────────────────────────────────────
# Spark + Docker path (optional, production-fidelity)
# ─────────────────────────────────────────────────────────────

spark-up: ## [spark] Start MinIO + Spark/Jupyter (Docker — first run pulls ~2 GB)
	$(COMPOSE) up -d
	@echo "  Jupyter → http://localhost:8888 (token: lakehouse)"
	@echo "  MinIO   → http://localhost:9001 (minioadmin / minioadmin)"

spark-smoke: ## [spark] Smoke test inside Spark container
	$(COMPOSE) exec -T spark python /workspace/scripts/verify.py

spark-data: ## [spark] Generate 1M-row Bronze (Spark version)
	$(COMPOSE) exec -T spark python /workspace/scripts/generate_data.py

spark-down: ## [spark] Stop Docker stack (data persists)
	$(COMPOSE) down

spark-clean: ## [spark] Stop AND wipe MinIO + ivy cache
	$(COMPOSE) down -v

.PHONY: help setup smoke test lab data data-ai run-all clean \
        simulate apple-up apple-smoke apple-data apple-status apple-down apple-clean \
        spark-up spark-smoke spark-data spark-down spark-clean
