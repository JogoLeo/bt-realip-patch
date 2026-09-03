#!/bin/bash
# ============================================================
# 宝塔面板 真实IP 自动修复脚本 (v2)
# 适用: 宝塔 11.x + 反向代理(含CDN等代理层)环境
#
# v2 相比 v1 的改进:
#   1) 不再要求面板看到的 remote_addr 必须是 127.0.0.1
#      很多环境里, 反代是用「本机内网IP」或「容器网关IP」连面板的
#      (例如 192.168.x.x / 172.17.x.x), 此时宝塔原有的
#          if ipaddr in ('127.0.0.1', '::1', 'localhost'):
#      判断不成立, 读 X-Forwarded-For 的整段分支被跳过,
#      只把 [-1] 改成 [0] 是无效的 —— 面板会一直显示反代机器自己的IP。
#      v2 把信任条件放宽为「回环 + 私有网段」, 覆盖上述场景。
#   2) 兼容 v1: 若代码里仍是 forwarded_ips[-1], 一并改为 [0]
#      (X-Forwarded-For 最左端 = 真实客户端IP, 最右端 = 上一层代理IP)。
#   3) 顶部设置 LC_ALL=C, 消除部分机器的 setlocale 警告。
#
# 前提: 反代必须把真实客户端IP正确放进 X-Forwarded-For 传下来。
#       若反代侧有「强制用 remote_addr 覆盖」的开关(某些反代工具的
#       "自动透传/一键优化"类功能), 会冲掉自定义的真实IP来源设置,
#       导致后端收到的 XFF 里全是内网IP —— 这种情况请先在反代侧关掉该开关,
#       本脚本无法在数据本身已被污染的情况下还原真实IP。
#
# 安全: 仅信任回环与私有网段。来自公网的直连不会被信任, 其 XFF 头会被忽略,
#       因此公网伪造 X-Forwarded-For 无效(仍需确保面板端口不对公网裸露)。
#
# 幂等: 已修复则静默退出(不写日志), 计划任务日常运行不产生噪音。
# 用法: bash bt_panel_realip_patch.sh
# ============================================================

set -u

# 规避部分机器未生成 en_US.UTF-8 导致的 setlocale 警告(仅影响日志观感,不影响逻辑)
export LC_ALL=C
unset LANG LANGUAGE 2>/dev/null

PUBLIC_PY="/www/server/panel/class/public.py"
BACKUP_DIR="/root/bt_patch_backup"
LOG="/var/log/bt_realip_patch.log"

# 优先用面板自带 python 编译,避免 .pyc 版本不一致
BT_PYTHON="$(ls /www/server/panel/pyenv/bin/python 2>/dev/null)"
[ -z "$BT_PYTHON" ] && BT_PYTHON="$(command -v python3 2>/dev/null || command -v python 2>/dev/null)"

log() { echo "[$(date '+%F %T')] $*" | tee -a "$LOG"; }

if [ ! -f "$PUBLIC_PY" ]; then
    log "ERROR: 找不到 $PUBLIC_PY,请确认本机已安装宝塔面板"
    exit 1
fi

if [ -z "$BT_PYTHON" ]; then
    log "ERROR: 找不到可用的 python,无法执行补丁"
    exit 1
fi

# 已应用 v2(存在特征变量)则静默退出,不写任何日志
if grep -q "_bt_ipaddr_trusted" "$PUBLIC_PY"; then
    exit 0
fi

log "检测到尚未应用 v2 增强,开始打补丁..."

# 备份原文件
mkdir -p "$BACKUP_DIR"
cp -p "$PUBLIC_PY" "$BACKUP_DIR/public.py.$(date '+%F_%H-%M-%S')"
log "已备份原文件到 $BACKUP_DIR"

RESULT="$("$BT_PYTHON" - "$PUBLIC_PY" <<'PYEOF'
import sys, re

path = sys.argv[1]
with open(path, 'r', encoding='utf-8') as f:
    src = f.read()

MARK = "_bt_ipaddr_trusted"
if MARK in src:
    print("ALREADY")
    sys.exit(0)

# 取出 GetClientIp() 整个函数体(到下一个顶层定义为止)
m = re.search(r"^def GetClientIp\(\):.*?(?=^\S|\Z)", src, re.M | re.S)
if not m:
    print("FUNC_NOT_FOUND")
    sys.exit(1)

body = m.group(0)
new = body

# (1) 兼容 v1: 取 X-Forwarded-For 最左端(真实客户端IP)
new = new.replace("forwarded_ips[-1]", "forwarded_ips[0]")

# (2) 放宽信任条件: 回环 + 私有网段(本机内网IP / 容器网关 / 同机房反代)
cond = re.compile(r"^([ \t]*)if[ \t]+ipaddr[ \t]+in[ \t]*\([^)]*\)[ \t]*:.*$", re.M)

def repl(mm):
    ind = mm.group(1)
    return (
        "{i}_bt_ipaddr_trusted = ipaddr in ('127.0.0.1', '::1', 'localhost')\n"
        "{i}if not _bt_ipaddr_trusted:\n"
        "{i}    try:\n"
        "{i}        import ipaddress as _bt_ipaddr\n"
        "{i}        _bt_ipv = _bt_ipaddr.ip_address(ipaddr)\n"
        "{i}        _bt_ipaddr_trusted = bool(_bt_ipv.is_loopback or _bt_ipv.is_private or _bt_ipv.is_link_local)\n"
        "{i}    except Exception:\n"
        "{i}        _bt_ipaddr_trusted = False\n"
        "{i}if _bt_ipaddr_trusted:  # 信任本地/内网反代(回环、同机内网IP、容器网关)".format(i=ind)
    )

new, n = cond.subn(repl, new, count=1)
if n == 0:
    print("COND_NOT_FOUND")
    sys.exit(1)

if new == body:
    print("NO_CHANGE")
    sys.exit(0)

out = src[:m.start()] + new + src[m.end():]
with open(path, 'w', encoding='utf-8') as f:
    f.write(out)
print("PATCHED")
PYEOF
)"

case "$RESULT" in
    PATCHED)
        log "补丁写入成功(信任条件已放宽 + XFF取最左)"
        ;;
    ALREADY|NO_CHANGE)
        log "无需修改"
        exit 0
        ;;
    FUNC_NOT_FOUND)
        log "ERROR: 未在 $PUBLIC_PY 中找到 GetClientIp(),面板结构可能已变化,请人工确认"
        exit 1
        ;;
    COND_NOT_FOUND)
        log "ERROR: 未找到 ipaddr 信任判断语句,面板结构可能已变化,请人工确认"
        exit 1
        ;;
    *)
        log "ERROR: 补丁执行异常: $RESULT"
        exit 1
        ;;
esac

if "$BT_PYTHON" -m py_compile "$PUBLIC_PY" 2>>"$LOG"; then
    log "语法检查通过"
else
    log "WARN: 语法检查未通过,请手动检查 $PUBLIC_PY(备份在 $BACKUP_DIR)"
fi

if bt restart >>"$LOG" 2>&1; then
    log "面板已重启,真实IP修复生效"
else
    log "WARN: bt restart 执行失败,请手动重启面板"
fi
