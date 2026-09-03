<?php
// 关键: 声明按纯文本渲染。否则浏览器按 HTML 处理, \n 会被当作空白符折叠, 所有输出挤成一行。
header('Content-Type: text/plain; charset=utf-8');

// 真实 IP 候选头, 按可靠度排序
// (CDN 私有头最可靠: 由 CDN 边缘节点写入, 不受后续反代链路污染)
$candidates = [
    'REMOTE_ADDR'      => $_SERVER['REMOTE_ADDR'] ?? '',
    'Eo-Client-Ip'     => $_SERVER['HTTP_EO_CLIENT_IP'] ?? '',        // CDN私有头
    'Eo-Connecting-Ip' => $_SERVER['HTTP_EO_CONNECTING_IP'] ?? '',    // CDN私有头
    'CF-Connecting-IP' => $_SERVER['HTTP_CF_CONNECTING_IP'] ?? '',    // CDN私有头
    'X-Real-IP'        => $_SERVER['HTTP_X_REAL_IP'] ?? '',
    'X-Forwarded-For'  => $_SERVER['HTTP_X_FORWARDED_FOR'] ?? '',
];

echo "===== 真实IP 候选头 =====\n";
foreach ($candidates as $name => $val) {
    echo str_pad($name, 18) . ': ' . ($val === '' ? 'not set' : $val) . "\n";
}

echo "\n===== 全部请求头 =====\n";
foreach (getallheaders() as $name => $value) {
    echo "$name: $value\n";
}
