# 宝塔面板真实IP自动修复脚本

> 适用环境：宝塔面板 11.x + 反向代理环境（如面板域名经 CDN 等代理层回源）

当宝塔面板经反向代理（如 CDN）回源时，面板登录日志、IP 白名单、封禁等功能只能看到**上一层代理的 IP**，而看不到真实客户端 IP。本脚本自动修复这个问题，并在面板升级覆盖后一键恢复。

## 问题根因

- 宝塔 **PHP 网站**由 Nginx 提供，开启「CDN IP 识别」后靠 Nginx 的 `real_ip` 模块把 `X-Forwarded-For` 里的真实 IP 重写进 `$remote_addr`，所以网站能拿到真实 IP。
- 宝塔 **面板本体**是一个独立的 Python/Flask 服务，取 IP 靠 `/www/server/panel/class/public.py` 里的 `GetClientIp()`，默认只取 `request.remote_addr`（即 TCP 对端 = 上一层代理的 IP），并不解析 `X-Forwarded-For`。
- 11.x 的 `GetClientIp()` 已有「本地代理信任」逻辑：当 `remote_addr` 为 `127.0.0.1` 时读取 `X-Forwarded-For`，但原版取的是 `forwarded_ips[-1]`（最后一个 = 代理层 IP）。在叠加了 CDN 等代理层后，真实客户端 IP 其实是 `forwarded_ips[0]`（最左边）。

**修复方式**：将 `real_ipaddr = forwarded_ips[-1]` 改为 `real_ipaddr = forwarded_ips[0]`。

## 脚本功能

`bt_panel_realip_patch.sh`：

- **自动检测**：检查 `public.py` 是否仍包含未修复的 `forwarded_ips[-1]`。
- **自动修补**：精确替换（仅改 `GetClientIp()` 内那一行，不会误伤其它代码）。
- **自动备份**：修补前把原文件备份到 `/root/bt_patch_backup/`。
- **自动重载**：修补后做语法检查并 `bt restart` 使生效。
- **幂等 & 静默**：已修复时直接静默退出、不写日志，适合放定时任务每天跑。

## 使用方法

### 1. 手动运行（立即修复）

```bash
# 把脚本传到服务器后：
chmod +x bt_panel_realip_patch.sh
bash bt_panel_realip_patch.sh
```

### 2. 配置定时任务（应对面板升级覆盖）

面板升级 / 修复会覆盖 `public.py`，把 `[-1]` 改回去。用定时任务每天自动检测并恢复：

**方式 A：宝塔面板自带「计划任务」（推荐）**

1. 宝塔面板 → 计划任务 → 添加任务
2. 任务类型：**Shell 脚本**
3. 执行周期：**每天**，时间选凌晨（如 04:00）
4. 脚本内容：`bash /root/bt_panel_realip_patch.sh`
5. 保存后点「执行」可立即验证一次

**方式 B：系统 crontab**

```bash
crontab -e
# 加入：
0 4 * * * bash /root/bt_panel_realip_patch.sh >> /var/log/bt_realip_patch.log 2>&1
```

> 日志位于 `/var/log/bt_realip_patch.log`。已修复的日子里脚本静默退出、不产生任何日志；只有在真正打补丁（如升级后）时才会记录。

## 注意事项

1. **面板升级会覆盖补丁**：这是改核心代码，每次升级后需重打，本脚本即为此设计。
2. **安全风险**：直接信任 `X-Forwarded-For` 理论上可被伪造。前提是**面板端口不能对公网裸露**，只允许经过可信的反代链路访问。
3. **IPv6 归属地**：修补后面板能正确显示真实 IPv6 地址，但**地区（省/市）查不到**——这是宝塔内置纯真 IP 库（`qqwry.dat`，IPv4 库）对 IPv6 几乎无覆盖所致，属数据库限制，非配置问题。若需地区显示，可让面板访问域名仅解析 IPv4（去掉 AAAA 记录）。
4. **SSH 登录通知的 IP**：宝塔 SSH 登录微信通知读的是服务器 sshd 日志里的来源 IP。若你用的是面板内「SSH 终端」，sshd 看到的是本机回环，通知只能是内网 IP（Web 终端固有限制）；若用真实 SSH 客户端但走了反向代理端口转发，sshd 看到的是转发器的内网 IP。此问题不在本脚本修复范围内，需另行处理（如 SSH 端口直连公网并加强安全）。

## 文件说明

| 文件 | 说明 |
|------|------|
| `bt_panel_realip_patch.sh` | 自动检测 / 修补 / 备份 / 重启脚本 |

## License

MIT
