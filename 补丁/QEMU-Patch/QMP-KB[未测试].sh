#!/bin/bash

# 监听物理键盘事件，通过 QMP input-send-event 注入到虚拟机
# 需要安装 evtest： sudo apt install evtest

# ===== 配置区 =====
# 查找键盘设备：
#   cat /proc/bus/input/devices | grep -B5 keyboard
#   ls -l /dev/input/by-id/
DEV="/dev/input/by-id/usb-2a7a_CASUE_USB_KB-event-kbd"   # 请改为实际键盘设备路径

HOST=127.0.0.1
PORT=5555
MAX=30         # 重试次数
DLY=10         # 每次重试等待秒数

# ===== 1. 建立 QMP 连接（带重试） =====
for ((i=0; i<MAX; i++)); do
    exec 3<>/dev/tcp/$HOST/$PORT 2>/dev/null && break
    echo "QMP 重试 $((i+1))/$MAX" >&2
    sleep $DLY
done

[ ! -e /dev/fd/3 ] && { echo "QMP 连接失败" >&2; exit 1; }

# 初始化 QMP
read -t2 -u3
echo '{"execute":"qmp_capabilities"}' >&3

# 后台清空 QMP 响应，防止缓冲区满
trap 'kill $reader_pid 2>/dev/null' EXIT
while read -r -u3; do :; done &
reader_pid=$!

# ===== 2. 按键名 -> QMP qcode 映射表 =====
declare -A KEY_MAP=(
    # 修饰键
    [KEY_LEFTSHIFT]=shift   [KEY_RIGHTSHIFT]=shift_r
    [KEY_LEFTCTRL]=ctrl     [KEY_RIGHTCTRL]=ctrl_r
    [KEY_LEFTALT]=alt       [KEY_RIGHTALT]=alt_r
    [KEY_LEFTMETA]=meta_l   [KEY_RIGHTMETA]=meta_r
    # 功能键
    [KEY_ESC]=esc           [KEY_ENTER]=enter        [KEY_SPACE]=space
    [KEY_BACKSPACE]=backspace [KEY_TAB]=tab
    [KEY_CAPSLOCK]=caps_lock [KEY_NUMLOCK]=num_lock [KEY_SCROLLLOCK]=scroll_lock
    [KEY_INSERT]=insert     [KEY_DELETE]=delete      [KEY_HOME]=home
    [KEY_END]=end           [KEY_PAGEUP]=pgup        [KEY_PAGEDOWN]=pgdn
    [KEY_UP]=up             [KEY_DOWN]=down          [KEY_LEFT]=left   [KEY_RIGHT]=right
    [KEY_F1]=f1 [KEY_F2]=f2 [KEY_F3]=f3 [KEY_F4]=f4
    [KEY_F5]=f5 [KEY_F6]=f6 [KEY_F7]=f7 [KEY_F8]=f8
    [KEY_F9]=f9 [KEY_F10]=f10 [KEY_F11]=f11 [KEY_F12]=f12
    # 小键盘
    [KEY_KP0]=kp_0 [KEY_KP1]=kp_1 [KEY_KP2]=kp_2 [KEY_KP3]=kp_3 [KEY_KP4]=kp_4
    [KEY_KP5]=kp_5 [KEY_KP6]=kp_6 [KEY_KP7]=kp_7 [KEY_KP8]=kp_8 [KEY_KP9]=kp_9
    [KEY_KPASTERISK]=kp_multiply [KEY_KPMINUS]=kp_subtract
    [KEY_KPPLUS]=kp_add [KEY_KPDOT]=kp_decimal [KEY_KPENTER]=kp_enter
    [KEY_KPSLASH]=kp_divide
    # 符号（常用）
    [KEY_MINUS]=minus       [KEY_EQUAL]=equal        [KEY_LEFTBRACE]=bracket_left
    [KEY_RIGHTBRACE]=bracket_right [KEY_SEMICOLON]=semicolon
    [KEY_APOSTROPHE]=apostrophe [KEY_GRAVE]=grave_accent
    [KEY_BACKSLASH]=backslash [KEY_COMMA]=comma      [KEY_DOT]=dot
    [KEY_SLASH]=slash       [KEY_SYSRQ]=print        [KEY_PAUSE]=pause
    [KEY_MENU]=menu
)

events=()   # 累积待发送的按键事件

# ===== 3. 监听 evtest 输出，处理并发送 =====
evtest "$DEV" 2>/dev/null | while read -r line; do
    if [[ $line =~ ^Event:\ time\ [^,]+,\ type\ [0-9]+\ \((.+)\),\ code\ [0-9]+\ \((.+)\),\ value\ (.+)$ ]]; then
        t=${BASH_REMATCH[1]}
        c=${BASH_REMATCH[2]}
        v=${BASH_REMATCH[3]}

        # 只处理键盘按键 (EV_KEY 且代码以 KEY_ 开头)
        if [[ $t == "EV_KEY" && $c == KEY_* ]]; then
            # 确定 qcode 名称
            if [ -n "${KEY_MAP[$c]}" ]; then
                key_qcode="${KEY_MAP[$c]}"
            else
                # 未在映射表中的键，去掉 KEY_ 前缀并转为小写
                key_qcode="${c#KEY_}"
                key_qcode="${key_qcode,,}"
            fi

            # 按下 (value=1) 或释放 (value=0)，忽略重复 (value=2)
            if [ "$v" -eq 1 ]; then
                events+=('{"type":"key","data":{"down":true,"key":{"type":"qcode","data":"'$key_qcode'"}}}')
            elif [ "$v" -eq 0 ]; then
                events+=('{"type":"key","data":{"down":false,"key":{"type":"qcode","data":"'$key_qcode'"}}}')
            fi
        fi
    elif [[ $line == *SYN_REPORT* ]]; then
        # 同步事件到来时，一次性发送所有累积的按键事件
        if [ ${#events[@]} -gt 0 ]; then
            IFS=','; printf '{"execute":"input-send-event","arguments":{"events":[%s]}}\n' "${events[*]}" >&3
            events=()
        fi
    fi
done


