#!/bin/bash
# ============================================================
# 宝塔面板 真实IP 问题诊断脚本
# 用途: 排查"补丁脚本执行成功(Successful)但面板IP识别依然不对"
# 用法: bash bt_realip_diagnose.sh
# 说明: 只读采集,不修改任何文件,可放心执行
# ============================================================

export LC_ALL=C
unset LANG LANGUAGE 2>/dev/null

PUBLIC_PY="/www/server/panel/class/public.py"
SEP="============================================================"
BT_PYTHON="$(ls /www/server/panel/pyenv/bin/python 2>/dev/null)"
[ -z "$BT_PYTHON" ] && BT_PYTHON="$(command -v python3 2>/dev/null || command -v python 2>/dev/null)"

echo "$SEP"
echo "[1] 宝塔版本 / 面板端口"
echo "$SEP"
grep -o '"version"[^,}]*' /www/server/panel/config/config.json 2>/dev/null || true
bt version 2>/dev/null | head -3 || true
PANEL_PORT="$(cat /www/server/panel/data/port.pl 2>/dev/null || echo "")"
echo "面板端口: ${PANEL_PORT:-未获取到}"
echo "--- 面板进程启动时间(用来确认打补丁后有没有真的重启过) ---"
ps -eo pid,lstart,comm 2>/dev/null | grep -iE "BT-Panel|BT-Task" | head -5 || echo "(未取到进程信息)"

echo
echo "$SEP"
echo "[2] GetClientIp() 当前源码"
echo "$SEP"
if [ ! -f "$PUBLIC_PY" ]; then
    echo "!! 未找到 $PUBLIC_PY  (路径不对, 补丁脚本所有判断都会失效)"
else
    grep -n "def GetClientIp" -A 30 "$PUBLIC_PY" || echo "!! 未找到 GetClientIp 函数"
fi

echo
echo "$SEP"
echo "[3] 补丁特征检测  (决定补丁脚本会不会动手)"
echo "$SEP"
if [ -f "$PUBLIC_PY" ]; then
    if grep -n "forwarded_ips\[-1\]" "$PUBLIC_PY"; then
        echo ">>> 命中 forwarded_ips[-1]  => 未修复, 补丁脚本应当打补丁"
    else
        echo ">>> 没有 forwarded_ips[-1]  => 补丁脚本会静默退出(误判为已修复) <== 高度可疑"
    fi
    echo "---"
    if grep -n "forwarded_ips\[0\]" "$PUBLIC_PY"; then
        echo ">>> 命中 forwarded_ips[0]  => 补丁已存在"
    else
        echo ">>> 没有 forwarded_ips[0]  => 补丁不存在"
    fi
    echo "---"
    if grep -n "X-Forwarded-For\|X-Real-Ip\|X-Real-IP" "$PUBLIC_PY" | head -10; then
        echo ">>> 上面是文件里所有出现代理头的地方"
    else
        echo "!! 完全没有代理头相关代码 => 新版结构大改, 需重写补丁"
    fi
    echo "---"
    if grep -n "_bt_ipaddr_trusted" "$PUBLIC_PY" | head -3; then
        echo ">>> v2 增强已应用(信任回环 + 私有网段, 跨机/内网反代可生效)"
    else
        echo "!! v2 增强未应用 => 面板仍只信任 127.0.0.1, 凡是反代用内网IP连过来的场景都不生效"
    fi
fi

echo
echo "$SEP"
echo "[4] 关键: 面板端口的实际来源IP (= 面板看到的 remote_addr)"
echo "$SEP"
echo "说明: 宝塔只在 remote_addr 是 127.0.0.1 / ::1 / localhost 时才去读 X-Forwarded-For。"
echo "      若来源是 Docker 网关(172.17.x)、反代机内网IP 等其它地址, XFF 分支会被整段跳过,"
echo "      此时把 [-1] 改成 [0] 完全无效 —— 这是『脚本跑成功但IP还是不对』第二常见的原因。"
echo
if [ -n "$PANEL_PORT" ]; then
    echo "--- 连到面板端口 ${PANEL_PORT} 的连接 (看来源/Peer 地址) ---"
    ss -tnp 2>/dev/null | grep ":${PANEL_PORT}" | head -20
    echo "(若上面为空: 当前无活跃连接, 请先在浏览器刷新面板页面, 再重跑本脚本)"
else
    echo "!! 取不到面板端口, 跳过"
fi

echo
echo "$SEP"
echo "[5] 面板记录的登录日志 (看面板实际把什么IP写进去了)"
echo "$SEP"
if [ -n "$BT_PYTHON" ]; then
"$BT_PYTHON" - <<'PYEOF' 2>&1 | head -20
import os, sqlite3
db = "/www/server/panel/data/default.db"
if not os.path.exists(db):
    print("未找到日志库, 跳过")
else:
    try:
        conn = sqlite3.connect(db)
        cur = conn.cursor()
        cur.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='logs'")
        if not cur.fetchone():
            print("没有 logs 表")
        else:
            cur.execute("SELECT id, addtime, type, log FROM logs ORDER BY id DESC LIMIT 8")
            rows = cur.fetchall()
            if not rows:
                print("logs 表为空")
            for r in rows:
                print(r)
        conn.close()
    except Exception as e:
        print("查询失败:", e)
PYEOF
else
    echo "!! 找不到可用 python, 跳过"
fi

echo
echo "$SEP"
echo "[6] locale 状态 (解释脚本顶部的 setlocale 警告)"
echo "$SEP"
locale 2>&1 | head -5
echo "--- 系统可用 locale ---"
locale -a 2>/dev/null | head -10

echo
echo "$SEP"
echo "[7] X-Forwarded-For 到底有没有传到面板 (最关键的一环)"
echo "$SEP"
echo "补丁生效的前提: 反代必须把真实客户端IP放进 X-Forwarded-For(或 X-Real-IP) 传给面板。"
echo "若反代没传这个头, 或传下去的是内网IP, 那代码改得再对也没用 —— 读出来是空或内网地址,"
echo "check_ip() 校验失败后会退回 remote_addr, 面板照样显示内网IP。"
echo
if [ -n "$PANEL_PORT" ]; then
    echo ">>> 现在请用浏览器访问或刷新一下你的面板页面, 脚本将抓包 20 秒"
    echo ">>> (20 秒内没有访问的话结果会是空的, 重跑本脚本即可)"
    TMP_CAP="$(mktemp 2>/dev/null)"
    [ -z "$TMP_CAP" ] && TMP_CAP="/tmp/bt_xff_cap.txt"
    if command -v tcpdump >/dev/null 2>&1 && command -v timeout >/dev/null 2>&1; then
        timeout 20 tcpdump -i any -A -s 0 "tcp port ${PANEL_PORT}" >"$TMP_CAP" 2>/dev/null
        echo "--- 抓到的代理头 ---"
        if grep -aiE "X-Forwarded-For|X-Real-IP" "$TMP_CAP" | head -20; then
            echo ">>> 上面就是面板实际收到的头。请确认最左边那一个是不是你的真实公网IP。"
        else
            echo "!! 一个 X-Forwarded-For / X-Real-IP 都没抓到"
            echo "   两种可能: a) 反代规则没有配置透传客户端IP;  b) 面板启用了SSL, 抓到的是密文(看下一段)"
        fi
        echo "--- 是否有明文HTTP(用来判断面板是不是HTTPS) ---"
        if grep -aiE "GET |POST |HTTP/1" "$TMP_CAP" | head -3; then
            echo ">>> 抓到明文HTTP, 上面的头信息可信"
        else
            echo "!! 没抓到明文HTTP => 面板很可能启用了SSL, 抓包是密文, 不能据此下结论"
            echo "   建议: 临时关掉面板SSL再抓一次, 或直接到反代配置里确认是否透传了 X-Forwarded-For"
        fi
        rm -f "$TMP_CAP"
    else
        echo "!! 系统缺少 tcpdump 或 timeout, 跳过抓包"
        echo "   请直接到反代配置里确认: 反代到面板端口的那条规则, 有没有透传 X-Forwarded-For"
    fi
else
    echo "!! 取不到面板端口, 跳过"
fi

echo
echo "$SEP"
echo "诊断完毕。请把 [3][4][7] 三段输出贴回来(重点看 [7])。"
echo "$SEP"
