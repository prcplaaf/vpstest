#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'
umask 077

SCRIPT_NAME="VPS One-Click Test"
VERSION="2.0.0"
TMP_DIR="$(mktemp -d -t vpstest.XXXXXX)"
trap 'rm -rf "${TMP_DIR}"' EXIT

MASK_IP="${VPSTEST_MASK_IP:-1}"
PING_COUNT="${VPSTEST_PING_COUNT:-6}"

need_cmd() {
  local cmd="$1"
  command -v "${cmd}" >/dev/null 2>&1
}

section() {
  echo
  echo "[*] $1"
  echo "---------------------------------------"
}

mask_ip() {
  local ip="$1"
  if [[ -z "${ip}" ]]; then
    echo "N/A"
    return
  fi
  if [[ "${MASK_IP}" != "1" ]]; then
    echo "${ip}"
    return
  fi
  if [[ "${ip}" == *":"* ]]; then
    echo "${ip}" | awk -F: '{print $1":"$2":"$3":"$4"::xxxx"}'
  else
    echo "${ip}" | awk -F. '{print $1"."$2".x.x"}'
  fi
}

press_enter() {
  echo
  read -r -p "按回车继续..." _
}

header() {
  clear || true
  cat <<EOF
=======================================
  ${SCRIPT_NAME} v${VERSION}
=======================================
安全默认：
1) 默认公网IP脱敏显示（VPSTEST_MASK_IP=0可关闭）
2) 不读取SSH密钥/账号敏感信息
3) 不写持久化日志，临时文件自动销毁
EOF
}

sys_info() {
  section "VPS 系统参数"
  local os kernel arch virt uptime_s cpu_model cpu_cores cpu_mhz loadavg
  local mem_total mem_used swap_total swap_used disk_root

  os="$(grep -E '^PRETTY_NAME=' /etc/os-release 2>/dev/null | cut -d= -f2- | tr -d '"' || echo Unknown)"
  kernel="$(uname -r 2>/dev/null || echo Unknown)"
  arch="$(uname -m 2>/dev/null || echo Unknown)"
  virt="$(systemd-detect-virt 2>/dev/null || echo Unknown)"
  uptime_s="$(uptime -p 2>/dev/null || uptime 2>/dev/null || echo Unknown)"
  cpu_model="$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2- | xargs || echo Unknown)"
  cpu_cores="$(nproc 2>/dev/null || echo Unknown)"
  cpu_mhz="$(awk -F: '/cpu MHz/{v=$2} END{gsub(/^ +| +$/,"",v); print v}' /proc/cpuinfo 2>/dev/null || echo Unknown)"
  loadavg="$(awk '{print $1" "$2" "$3}' /proc/loadavg 2>/dev/null || echo Unknown)"
  mem_total="$(free -h 2>/dev/null | awk '/Mem:/ {print $2}' || echo Unknown)"
  mem_used="$(free -h 2>/dev/null | awk '/Mem:/ {print $3}' || echo Unknown)"
  swap_total="$(free -h 2>/dev/null | awk '/Swap:/ {print $2}' || echo Unknown)"
  swap_used="$(free -h 2>/dev/null | awk '/Swap:/ {print $3}' || echo Unknown)"
  disk_root="$(df -h / 2>/dev/null | awk 'NR==2{print $2" total, "$3" used, "$4" avail ("$5")"}' || echo Unknown)"

  echo "OS             : ${os}"
  echo "Kernel         : ${kernel}"
  echo "Arch           : ${arch}"
  echo "Virtualization : ${virt}"
  echo "Uptime         : ${uptime_s}"
  echo "CPU            : ${cpu_model}"
  echo "vCPU           : ${cpu_cores}"
  echo "CPU MHz        : ${cpu_mhz}"
  echo "Load Avg       : ${loadavg}"
  echo "Memory         : ${mem_used} / ${mem_total}"
  echo "Swap           : ${swap_used} / ${swap_total}"
  echo "Disk(/)        : ${disk_root}"
}

ip_asn_info() {
  section "公网 / ASN / 地理信息（脱敏）"
  local ip4 ip6 info
  ip4="$(curl -4 -fsS --max-time 8 https://api.ipify.org 2>/dev/null || true)"
  ip6="$(curl -6 -fsS --max-time 8 https://api64.ipify.org 2>/dev/null || true)"

  echo "IPv4           : $(mask_ip "${ip4}")"
  echo "IPv6           : $(mask_ip "${ip6}")"

  info="$(curl -fsS --max-time 8 https://ipinfo.io/json 2>/dev/null || true)"
  if [[ -n "${info}" ]]; then
    echo "ASN/Org        : $(echo "${info}" | sed -n 's/.*"org"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
    echo "Country/City   : $(echo "${info}" | sed -n 's/.*"country"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)/$(echo "${info}" | sed -n 's/.*"city"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
  else
    echo "ASN/Geo        : N/A"
  fi
}

latency_test() {
  section "延迟 / 抖动 / 丢包测试"
  local targets=(
    "1.1.1.1:Cloudflare"
    "8.8.8.8:Google DNS"
    "223.5.5.5:AliDNS"
    "114.114.114.114:114DNS"
  )
  for item in "${targets[@]}"; do
    local host name out
    host="${item%%:*}"; name="${item##*:}"
    echo "- ${name} (${host})"
    out="$(ping -c "${PING_COUNT}" -W 2 "${host}" 2>/dev/null || true)"
    if [[ -z "${out}" ]]; then
      echo "  result        : timeout"
      continue
    fi
    echo "${out}" | awk -F',' '/packets transmitted/ {gsub(/^ +| +$/,"",$3); print "  packet loss    : "$3}'
    echo "${out}" | awk -F'/' '/^rtt|^round-trip/ {printf "  avg latency    : %sms\n  jitter(approx) : %sms\n", $5, ($7-$4)}'
  done
}

return_route_test() {
  section "三网回程路由"
  local targets=(
    "202.96.209.5:中国电信"
    "210.22.70.3:中国联通"
    "221.179.155.161:中国移动"
  )
  for item in "${targets[@]}"; do
    local host name
    host="${item%%:*}"; name="${item##*:}"
    echo
    echo "- ${name} (${host})"
    if need_cmd traceroute; then
      traceroute -n -w 1 -q 1 -m 18 "${host}" 2>/dev/null | head -n 22 || echo "  traceroute 失败"
    else
      echo "  未安装 traceroute"
    fi
  done
}

mtr_quality_test() {
  section "链路质量（MTR 简测）"
  local targets=("1.1.1.1" "8.8.8.8" "223.5.5.5")
  if ! need_cmd mtr; then
    echo "未安装 mtr，跳过。"
    return
  fi
  for host in "${targets[@]}"; do
    echo "- Target ${host}"
    mtr -n -r -c 10 "${host}" 2>/dev/null | tail -n 8 || echo "  mtr 失败"
  done
}

stream_unlock_test() {
  section "流媒体解锁（主流基础检测）"
  local ua="Mozilla/5.0 vpstest"
  local sites=(
    "Netflix|https://www.netflix.com/title/81215567|200"
    "YouTube|https://www.youtube.com/premium|200"
    "Disney+|https://www.disneyplus.com/|200,301,302"
    "PrimeVideo|https://www.primevideo.com/|200,301,302"
    "HBO Max|https://play.max.com/|200,301,302"
    "TVBAnywhere|https://uapisfm.tvbanywhere.com.sg/geoip/check/platform/android|200"
  )
  for row in "${sites[@]}"; do
    local name url expect code ok
    name="${row%%|*}"
    url="$(echo "${row}" | awk -F'|' '{print $2}')"
    expect="$(echo "${row}" | awk -F'|' '{print $3}')"
    code="$(curl -fsS -A "${ua}" -o /dev/null -w '%{http_code}' --max-time 10 "${url}" 2>/dev/null || echo 000)"
    ok="No"
    IFS=',' read -r -a exp_codes <<< "${expect}"
    for e in "${exp_codes[@]}"; do
      if [[ "${code}" == "${e}" ]]; then ok="Yes"; break; fi
    done
    echo "${name} : HTTP ${code} (${ok})"
  done
  echo "提示：最终可用性以账号实际播放为准。"
}

dns_quality_test() {
  section "DNS 解析质量"
  local domains=("google.com" "youtube.com" "netflix.com" "cloudflare.com")
  if ! need_cmd dig; then
    echo "未安装 dig，跳过。"
    return
  fi
  for d in "${domains[@]}"; do
    echo "- ${d}"
    dig +time=2 +tries=1 +short "${d}" | head -n 3
  done
  echo
  echo "Resolver       : $(awk '/^nameserver/{print $2}' /etc/resolv.conf 2>/dev/null | paste -sd ',' -)"
}

port_connectivity_test() {
  section "常见端口出站连通性"
  local checks=(
    "443|1.1.1.1|HTTPS"
    "53|8.8.8.8|DNS"
    "80|example.com|HTTP"
    "25|smtp.gmail.com|SMTP"
  )
  if ! need_cmd timeout; then
    echo "缺少 timeout，跳过。"
    return
  fi
  for row in "${checks[@]}"; do
    local port host name
    port="${row%%|*}"
    host="$(echo "${row}" | awk -F'|' '{print $2}')"
    name="$(echo "${row}" | awk -F'|' '{print $3}')"
    if timeout 3 bash -c "</dev/tcp/${host}/${port}" >/dev/null 2>&1; then
      echo "${name} (${host}:${port}) : Open"
    else
      echo "${name} (${host}:${port}) : Blocked/Timeout"
    fi
  done
}

disk_cpu_bench() {
  section "经典性能：CPU + 磁盘I/O + 下载速率"
  local cpu_result="N/A"
  if need_cmd openssl; then
    cpu_result="$(openssl speed -seconds 3 sha256 2>/dev/null | awk '/sha256/{print $(NF-1)" "$(NF)}' | tail -n 1)"
  fi
  echo "CPU(OpenSSL)   : ${cpu_result}"

  local io_file="${TMP_DIR}/io.test"
  local dd_out
  dd_out="$( (time dd if=/dev/zero of="${io_file}" bs=1M count=1024 conv=fdatasync status=none) 2>&1 || true )"
  echo "Disk Write      : $(echo "${dd_out}" | awk '/real/{print $0}' | head -n1)"

  local speed
  speed="$(curl -L -o /dev/null --max-time 35 -w '%{speed_download}' https://cachefly.cachefly.net/100mb.test 2>/dev/null || echo 0)"
  awk -v bps="${speed}" 'BEGIN {printf "Download        : %.2f Mbps\n", (bps*8)/(1024*1024)}'
}

security_baseline() {
  section "安全基线检查（只读）"
  echo "Root Login SSH  : $(grep -Ei '^PermitRootLogin' /etc/ssh/sshd_config 2>/dev/null | tail -n1 || echo 'Unknown')"
  echo "PasswordAuth    : $(grep -Ei '^PasswordAuthentication' /etc/ssh/sshd_config 2>/dev/null | tail -n1 || echo 'Unknown')"
  echo "Firewall(nft)   : $(need_cmd nft && echo Installed || echo Missing)"
  echo "Firewall(ufw)   : $(need_cmd ufw && ufw status 2>/dev/null | head -n1 || echo Missing)"
  echo "Fail2ban        : $(need_cmd fail2ban-client && fail2ban-client status 2>/dev/null | head -n1 || echo Missing)"
  echo "Kernel Updates  : $(need_cmd unattended-upgrades && echo Enabled-tool-present || echo Unknown)"
  echo "建议            : 禁用SSH密码登录、仅密钥、启用防火墙与fail2ban。"
}

quick_report() {
  section "脱敏快速报告"
  local report="${TMP_DIR}/vpstest-report.txt"
  {
    echo "# VPS Test Report"
    echo "# Time: $(date -u +'%Y-%m-%dT%H:%M:%SZ')"
    sys_info
    ip_asn_info
    latency_test
    stream_unlock_test
  } > "${report}" 2>&1
  cat "${report}"
  echo
  echo "报告路径（临时）: ${report}"
  echo "提示：脚本退出后该文件会自动删除。"
}

run_all() {
  sys_info
  ip_asn_info
  latency_test
  return_route_test
  mtr_quality_test
  stream_unlock_test
  dns_quality_test
  port_connectivity_test
  disk_cpu_bench
  security_baseline
}

menu() {
  cat <<'EOF'

请选择功能：
  1) 延迟/抖动/丢包
  2) 三网回程路由
  3) MTR链路质量
  4) 流媒体解锁（主流）
  5) VPS系统参数
  6) 公网/ASN/地理信息
  7) DNS解析质量
  8) 常见端口连通性
  9) 经典性能（CPU/磁盘/下载）
  a) 安全基线检查
  r) 脱敏快速报告
  0) 一键全测
  q) 退出
EOF
}

main() {
  while true; do
    header
    menu
    read -r -p "输入选项并回车: " choice
    case "${choice}" in
      1) latency_test ;;
      2) return_route_test ;;
      3) mtr_quality_test ;;
      4) stream_unlock_test ;;
      5) sys_info ;;
      6) ip_asn_info ;;
      7) dns_quality_test ;;
      8) port_connectivity_test ;;
      9) disk_cpu_bench ;;
      a|A) security_baseline ;;
      r|R) quick_report ;;
      0) run_all ;;
      q|Q) echo "退出。"; break ;;
      *) echo "无效选项，请重试。" ;;
    esac
    press_enter
  done
}

main "$@"