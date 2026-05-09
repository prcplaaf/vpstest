#!/usr/bin/env bash
set -euo pipefail

REPO_URL="${REPO_URL:-https://github.com/yourname/vps-oneclick-test.git}"
INSTALL_DIR="${INSTALL_DIR:-/opt/vps-oneclick-test}"
BIN_PATH="/usr/local/bin/vpstest"

need_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "[!] 请使用 root 执行安装：sudo bash install.sh"
    exit 1
  fi
}

install_deps() {
  echo "[*] 安装依赖..."
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update -y
    apt-get install -y bash curl wget ca-certificates iproute2 iputils-ping traceroute mtr-tiny dnsutils lsb-release procps coreutils
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y bash curl wget ca-certificates iproute iputils traceroute mtr bind-utils procps-ng coreutils
  elif command -v yum >/dev/null 2>&1; then
    yum install -y bash curl wget ca-certificates iproute iputils traceroute mtr bind-utils procps-ng coreutils
  else
    echo "[!] 未识别的包管理器，请手动安装依赖：curl/wget/ping/traceroute/mtr/dig"
  fi
}

install_files() {
  echo "[*] 安装脚本到 ${INSTALL_DIR}"
  mkdir -p "${INSTALL_DIR}"

  if [[ -f ./vps-test.sh ]]; then
    cp -f ./vps-test.sh "${INSTALL_DIR}/vps-test.sh"
  else
    echo "[*] 本地未找到 vps-test.sh，尝试从仓库下载..."
    mkdir -p "${INSTALL_DIR}"
    curl -fsSL "${REPO_URL%/}/raw/main/vps-test.sh" -o "${INSTALL_DIR}/vps-test.sh"
  fi

  chmod 700 "${INSTALL_DIR}/vps-test.sh"
  chown root:root "${INSTALL_DIR}/vps-test.sh"

  cat > "${BIN_PATH}" <<'EOF'
#!/usr/bin/env bash
exec /opt/vps-oneclick-test/vps-test.sh "$@"
EOF
  chmod 755 "${BIN_PATH}"
  chown root:root "${BIN_PATH}"
}

finish_msg() {
  echo
  echo "[+] 安装完成。"
  echo "[+] 运行命令：vpstest"
  echo "[+] 卸载命令：rm -rf ${INSTALL_DIR} ${BIN_PATH}"
}

need_root
install_deps
install_files
finish_msg