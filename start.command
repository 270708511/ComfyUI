
#!/bin/bash
set -euo pipefail

# Always run from the repository root (script location).
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

HOST="127.0.0.1"
PORT="${COMFYUI_PORT:-8189}"
SHARED_DIR="${COMFYUI_SHARED_DIR:-/Users/Laven/ComfyUI-Shared}"
WAIT_SECONDS=30
AUTO_UPDATE="${COMFYUI_AUTO_UPDATE:-1}"
REQ_FILE="$SCRIPT_DIR/requirements.txt"
URL="http://${HOST}:${PORT}"

echo "[ComfyUI] Working directory: $SCRIPT_DIR"
echo "[ComfyUI] Shared directory: $SHARED_DIR"

# 1. 检查/创建/修复 .venv 虚拟环境
if [[ ! -d ".venv" ]]; then
  echo "[ComfyUI] No .venv found, creating virtual environment..."
  python3 -m venv .venv
fi

source .venv/bin/activate
PYTHON_BIN="$SCRIPT_DIR/.venv/bin/python"

if [[ ! -x "$PYTHON_BIN" ]]; then
  echo "[ComfyUI] Error: python not found in .venv, recreating..."
  rm -rf .venv
  python3 -m venv .venv
  source .venv/bin/activate
  PYTHON_BIN="$SCRIPT_DIR/.venv/bin/python"
fi

echo "[ComfyUI] Python: $PYTHON_BIN"


# 2. 升级 pip/setuptools/wheel（已禁用自动升级，需手动升级时请自行执行）
# "$PYTHON_BIN" -m pip install --upgrade pip wheel

# 3. 检查并安装 ComfyUI 依赖（已禁用自动安装，需手动安装时请自行执行）
# "$PYTHON_BIN" -m pip install -r "$REQ_FILE"

# 4. comfyui-manager 检查/安装/升级（已禁用自动升级，需手动升级时请自行执行）
# echo "[ComfyUI] Checking comfyui-manager..."
# if ! "$PYTHON_BIN" -m pip show comfyui-manager >/dev/null 2>&1; then
#   echo "[ComfyUI] comfyui-manager not found, installing..."
#   "$PYTHON_BIN" -m pip install -U comfyui-manager
# else
#   echo "[ComfyUI] comfyui-manager found, upgrading..."
#   "$PYTHON_BIN" -m pip install -U comfyui-manager
# fi

# 6. 依赖检查与原有逻辑...

check_core_requirements() {
  "$PYTHON_BIN" - "$REQ_FILE" <<'PY'
import re
import sys
from importlib.metadata import PackageNotFoundError, version

requirements_path = sys.argv[1]
semver = re.compile(r"^(\d+)\.(\d+)\.(\d+)$")


def parse_semver(v: str):
  m = semver.match(v)
  if not m:
    return None
  return tuple(int(x) for x in m.groups())


def parse_requirement_line(line: str):
  line = line.split("#", 1)[0].strip()
  if not line:
    return None

  op = "==" if "==" in line else ">=" if ">=" in line else None
  if op is None:
    return None

  name, required_version = (part.strip() for part in line.split(op, 1))
  name = name.split("[", 1)[0].strip()
  required_tuple = parse_semver(required_version)
  if not name or required_tuple is None:
    return None
  return name, required_version, required_tuple


missing = []
outdated = []

try:
  with open(requirements_path, "r", encoding="utf-8") as f:
    lines = f.readlines()
except FileNotFoundError:
  print(f"[ComfyUI] Error: requirements file not found: {requirements_path}")
  sys.exit(2)

for raw_line in lines:
  parsed = parse_requirement_line(raw_line)
  if parsed is None:
    continue

  name, required_str, required_tuple = parsed

  try:
    installed_str = version(name)
  except PackageNotFoundError:
    missing.append((name, required_str))
    continue

  installed_tuple = parse_semver(installed_str)
  if installed_tuple is None:
    continue
  if installed_tuple < required_tuple:
    outdated.append((name, installed_str, required_str))

if missing or outdated:
  print("[ComfyUI] Core dependency mismatch detected.")
  for name, req in missing:
    print(f"  - missing: {name} (required >= {req})")
  for name, installed, req in outdated:
    print(f"  - outdated: {name} ({installed} < {req})")
  sys.exit(20)

print("[ComfyUI] Core dependencies are up to date.")
sys.exit(0)
PY
}


echo "[ComfyUI] Checking core dependencies..."
set +e
check_core_requirements
REQ_STATUS=$?
set -e

if [[ "$REQ_STATUS" -eq 20 ]]; then
  if [[ "$AUTO_UPDATE" != "1" ]]; then
    echo "[ComfyUI] Error: dependency update is required, but auto-update is disabled (COMFYUI_AUTO_UPDATE=$AUTO_UPDATE)."
    echo "[ComfyUI] Run: $PYTHON_BIN -m pip install -r $REQ_FILE"
    exit 1
  fi

  echo "[ComfyUI] Updating core dependencies from requirements.txt ..."
  PIP_ARGS=(--retries 6 --timeout 120 --resume-retries 6 -r "$REQ_FILE")
  if [[ -n "${COMFYUI_PIP_EXTRA_ARGS:-}" ]]; then
    # shellcheck disable=SC2206
    EXTRA_ARGS=(${COMFYUI_PIP_EXTRA_ARGS})
    PIP_ARGS+="${EXTRA_ARGS[@]}"
  fi
  "$PYTHON_BIN" -m pip install "${PIP_ARGS[@]}"

  echo "[ComfyUI] Re-checking core dependencies..."
  set +e
  check_core_requirements
  REQ_STATUS=$?
  set -e
  if [[ "$REQ_STATUS" -ne 0 ]]; then
    echo "[ComfyUI] Error: dependency update did not complete successfully."
    echo "[ComfyUI] Retry manually: $PYTHON_BIN -m pip install -r $REQ_FILE"
    exit 1
  fi
elif [[ "$REQ_STATUS" -ne 0 ]]; then
  echo "[ComfyUI] Error: failed to check dependencies."
  exit 1
fi

if lsof -iTCP:"$PORT" -sTCP:LISTEN -n -P >/dev/null 2>&1; then
  echo "[ComfyUI] Error: port $PORT is already in use."
  lsof -iTCP:"$PORT" -sTCP:LISTEN -n -P || true
  exit 1
fi

open_comfyui_window() {
  # Disabled: do not open browser window on startup
  # if command -v open >/dev/null 2>&1; then
  #   if open -Ra "Google Chrome" >/dev/null 2>&1; then
  #     open -na "Google Chrome" --args --app="$URL" >/dev/null 2>&1 || open "$URL" >/dev/null 2>&1 || true
  #   else
  #     open "$URL" >/dev/null 2>&1 || true
  #   fi
  # fi
  return 0
}

wait_and_open() {
  for ((i = 1; i <= WAIT_SECONDS; i++)); do
    if curl --silent --fail --max-time 2 "$URL" >/dev/null 2>&1; then
      open_comfyui_window
      return 0
    fi
    sleep 1
  done
  echo "[ComfyUI] Warning: server did not respond at $URL within ${WAIT_SECONDS}s."
  return 0
}

wait_and_open &
WATCHER_PID=$!
trap 'kill "$WATCHER_PID" >/dev/null 2>&1 || true' EXIT

echo "[ComfyUI] Starting server at $URL"
echo "[ComfyUI] Press Ctrl+C in this window to stop."

"$PYTHON_BIN" main.py \
  --port "$PORT" \
  --listen "$HOST" \
  --base-directory "$SHARED_DIR" \
  --enable-manager \
  --input-directory "$SHARED_DIR/input" \
  --output-directory "$SHARED_DIR/output" \
  --user-directory "$SHARED_DIR/user" \
  "$@"
