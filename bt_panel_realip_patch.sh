#!/bin/bash
# ============================================================
# 宝塔面板 真实IP 自动修复脚本
# 适用: 宝塔 11.x + 反向代理(含CDN等代理层)环境
# 背景: 宝塔升级会覆盖 /www/server/panel/class/public.py,
#       导致 GetClientIp() 变回取 X-Forwarded-For 最后一个IP(上层代理IP)。
#       本脚本自动检测并修复为取第一个(真实客户端)IP,然后重启面板。
# 用法: bash bt_panel_realip_patch.sh
# ============================================================

set -u

PUBLIC_PY="/www/server/panel/class/public.py"
BACKUP_DIR="/root/bt_patch_backup"
LOG="/var/log/bt_realip_patch.log"

# 优先用面板自带 python 编译,避免 .pyc 版本不一致
BT_PYTHON="$(ls /www/server/panel/pyenv/bin/python 2>/dev/null)"
[ -z "$BT_PYTHON" ] && BT_PYTHON="$(command -v python3 || command -v python)"

log() { echo "[$(date '+%F %T')] $*" | tee -a "$LOG"; }

if [ ! -f "$PUBLIC_PY" ]; then
    log "ERROR: 找不到 $PUBLIC_PY,请确认本机已安装宝塔面板"
    exit 1
fi

# 已经修复(文件里没有 forwarded_ips[-1])则静默退出,不写任何日志
# 这样定时任务每天跑,在不需要处理时不会在日志里产生任何输出
if ! grep -q "forwarded_ips\[-1\]" "$PUBLIC_PY"; then
    exit 0
fi

log "检测到未修复代码,开始打补丁..."

# 备份原文件
mkdir -p "$BACKUP_DIR"
cp -p "$PUBLIC_PY" "$BACKUP_DIR/public.py.$(date '+%F_%H-%M-%S')"
log "已备份原文件到 $BACKUP_DIR"

# 精确替换 GetClientIp 内的 forwarded_ips[-1] -> forwarded_ips[0]
"$BT_PYTHON" - "$PUBLIC_PY" <<'PYEOF'
import sys
path = sys.argv[1]
with open(path, 'r', encoding='utf-8') as f:
    src = f.read()
old = "real_ipaddr = forwarded_ips[-1]"
new = "real_ipaddr = forwarded_ips[0]"
if old in src:
    src = src.replace(old, new)
    with open(path, 'w', encoding='utf-8') as f:
        f.write(src)
    print("PATCHED")
else:
    print("NO_MATCH")
PYEOF

# 校验:下面 grep 的 forwarded_ips\[0\] 是"字面字符串"匹配(确认文件里有已修补的代码文本),
# 不是判断列表长度是否为0。只有本脚本真正打过补丁时才会执行到这里。
if grep -q "forwarded_ips\[0\]" "$PUBLIC_PY"; then
    log "补丁写入成功"
    if "$BT_PYTHON" -m py_compile "$PUBLIC_PY" 2>>"$LOG"; then
        log "语法检查通过"
    else
        log "WARN: 语法检查未通过,请手动检查"
    fi
    if bt restart >>"$LOG" 2>&1; then
        log "面板已重启,真实IP修复生效"
    else
        log "WARN: bt restart 执行失败,请手动重启面板"
    fi
else
    log "ERROR: 补丁未生效,请手动检查 $PUBLIC_PY"
    exit 1
fi
