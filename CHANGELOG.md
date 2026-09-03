# 更新日志

本项目所有值得记录的变更都写在这里。格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)。

## [2.0.0] - 2026-09-03

### 新增

- **放宽 IP 信任条件**（核心修复）：把 `GetClientIp()` 里的
  `ipaddr in ('127.0.0.1', '::1', 'localhost')` 改为「回环 **+** 私有网段」
  （`ipaddress` 的 `is_loopback` / `is_private` / `is_link_local`）。
  解决跨机反代、容器网关（`172.17.0.1`）等场景下读 `X-Forwarded-For` 的分支**完全不执行**、
  面板一直显示反代机器自己 IP 的问题。
- `bt_realip_diagnose.sh`：只读诊断脚本，排查「脚本跑成功、计划任务显示 Successful，但 IP 还是不对」。
  采集面板端口实际来源 IP、`GetClientIp()` 当前源码、补丁特征、面板进程启动时间，并抓包显示真实请求头。
- `ip.php`：真实 IP 探针页，按可靠度列出各候选头（含 CDN 私有头）。

### 修复

- 消除部分机器上 `setlocale: LC_ALL: cannot change locale (en_US.UTF-8)` 的警告（脚本内 `export LC_ALL=C`）。
- 找不到 `GetClientIp()` 或信任判断语句时**报错退出**，不再静默跳过 —— 避免"以为修好了其实没修"。

### 改进

- 幂等判定改用具名特征变量 `_bt_ipaddr_trusted`，不再依赖 `forwarded_ips[-1]` 是否存在。
  旧判定在面板代码结构变化时会误判为"已修复"而直接跳过，导致补丁实际上从没打上。
- 文档补充排查提示与四步验证法（先探明真实 IP 藏在哪个头，再验证代码、来源 IP、最终效果）。

### 说明

- 开发过程中曾尝试过一版「改读 CDN 私有头以绕过被污染的 XFF」的方案，
  后确认根因在反代侧开关（关掉后 XFF 数据本身恢复正确），该方案随之撤销，未纳入发布。
  若遇到反代用 `$remote_addr` **覆盖** XFF（而非 `$proxy_add_x_forwarded_for` **追加**）的情况，
  数据本身已被污染，改面板代码无效 —— 需在反代侧解决，README 的「排查提示」一节有详述。

## [1.0.0] - 2026-07-21

### 新增

- 首个版本：把 `GetClientIp()` 中 `real_ipaddr = forwarded_ips[-1]` 改为 `forwarded_ips[0]`，
  取 `X-Forwarded-For` 最左端（真实客户端 IP）而非最右端（上一层代理 IP）。
- 打补丁前自动备份到 `/root/bt_patch_backup/`，改完做语法校验并 `bt restart`。
- 幂等且静默：已修复时直接退出、不写日志，适合放定时任务应对面板升级覆盖。
