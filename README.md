# VPS One-Click Test Script

一个偏安全、易用、功能完整的 VPS 一键测试脚本项目，支持交互式菜单和一键全测。

## 功能列表（一次配齐）

- 延迟/抖动/丢包测试（多目标）
- 三网回程路由（电信/联通/移动常见目标）
- MTR 链路质量简测
- 流媒体解锁主流基础检测（Netflix/YouTube/Disney+/PrimeVideo/HBO Max/TVB）
- VPS 参数检测（系统、CPU、内存、磁盘、负载、虚拟化）
- 公网 IP + ASN + 地理信息（默认脱敏）
- DNS 解析质量检测
- 常见端口出站连通性检查（443/53/80/25）
- 经典性能测试（OpenSSL CPU、磁盘 I/O、下载速率）
- 安全基线检查（SSH 配置、防火墙、Fail2ban）
- 脱敏快速报告（临时文件，退出自动删除）
- 一键全测

## 安全设计

- 默认开启公网 IP 脱敏显示（可 `export VPSTEST_MASK_IP=0` 关闭）
- 不读取 SSH 密钥、账号等敏感信息
- 不写持久化日志，临时目录自动清理
- 全程只读探测，不执行危险系统改动
- `set -euo pipefail` + `umask 077`，降低脚本风险

## 目录结构

- `install.sh` 安装脚本
- `vps-test.sh` 主脚本

## 使用方式

### 1) 安装

```bash
chmod +x install.sh vps-test.sh
sudo bash install.sh
```
或者一键脚本：
```bash
curl -fsSL https://raw.githubusercontent.com/pecplaaf/vpstest/main/install.sh | sudo bash
```

### 2) 启动

```bash
vpstest
```

## 菜单快捷键

- `1` 延迟/抖动/丢包
- `2` 三网回程路由
- `3` MTR链路质量
- `4` 流媒体解锁
- `5` VPS系统参数
- `6` 公网/ASN/地理信息
- `7` DNS解析质量
- `8` 端口连通性
- `9` 经典性能
- `a` 安全基线检查
- `r` 脱敏快速报告
- `0` 一键全测
- `q` 退出

## 建议

- 流媒体结果是基础可达性判断，最终以账号实测播放为准。
- 建议在新机器上线前先跑 `a` 安全基线，再跑 `0` 一键全测。

