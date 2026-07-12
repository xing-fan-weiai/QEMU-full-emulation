#!/bin/bash

#监听鼠标通过 QMP发送

#找鼠标	cat /proc/bus/input/devices | grep -B5 mouse
#找鼠标	ls -l /dev/input/by-id/

DEV="/dev/input/by-id/usb-E-Signal_USB_Gaming_Mouse-event-mouse"
HOST=127.0.0.1 PORT=4444 MAX=30 DLY=10		#三分钟	重试30次  等待10秒

# ---------- 1. 建立 QMP 连接（重试机制） ----------
for ((i=0; i<MAX; i++)); do
    exec 3<>/dev/tcp/$HOST/$PORT 2>/dev/null && break
    echo "QMP 重试 $((i+1))/$MAX" >&2
    sleep $DLY
done
# 若文件描述符 3 未成功打开，则退出
[ ! -e /dev/fd/3 ] && { echo "QMP 连接失败" >&2; exit 1; }

# 初始化 QMP 能力（丢弃欢迎信息，发送能力协商）
read -t2 -u3    # 读取并忽略欢迎信息
echo '{"execute":"qmp_capabilities"}' >&3

# 后台进程：持续清空 QMP 响应，防止缓冲区满
trap 'kill $reader_pid 2>/dev/null' EXIT
while read -r -u3; do :; done &
reader_pid=$!

dx=0 dy=0 events=()
# 按键名到 QMP 按钮名的映射表
declare -A BTN=(
    [BTN_LEFT]=left [BTN_RIGHT]=right [BTN_MIDDLE]=middle
    [BTN_SIDE]=side [BTN_EXTRA]=extra
)

# ---------- 2. 监听 evtest 输出并处理事件 ----------
evtest "$DEV" 2>/dev/null | while read -r line; do
    # 解析标准 evtest 事件行：类型、代码、值
    if [[ $line =~ ^Event:\ time\ [^,]+,\ type\ [0-9]+\ \((.+)\),\ code\ [0-9]+\ \((.+)\),\ value\ (.+)$ ]]; then
        t=${BASH_REMATCH[1]}  # 事件类型名，如 EV_REL、EV_KEY
        c=${BASH_REMATCH[2]}  # 事件代码名，如 REL_X、BTN_LEFT
        v=${BASH_REMATCH[3]}  # 事件值

        case $t in
            EV_REL)
                case $c in
                    REL_X) dx=$((dx + v)) ;;            # 相对位移X
                    REL_Y) dy=$((dy + v)) ;;            # 相对位移Y
                    REL_WHEEL)
                        # 滚轮方向处理：正值为上滚，负值为下滚
                        btn=wheel-up; [ $v -lt 0 ] && btn=wheel-down
                        # 生成按下/松开事件对，次数为滚轮步数
                        for ((k=${v#-}; k>0; k--)); do
                            events+=('{"type":"btn","data":{"down":true,"button":"'$btn'"}}')
                            events+=('{"type":"btn","data":{"down":false,"button":"'$btn'"}}')
                        done ;;
                esac ;;
            EV_KEY)
                # 如果是已知的鼠标按键，加入事件队列
                [ -n "${BTN[$c]}" ] && {
                    down=false; [ $v -eq 1 ] && down=true
                    events+=('{"type":"btn","data":{"down":'$down',"button":"'${BTN[$c]}'"}}')
                } ;;
        esac
    elif [[ $line == *SYN_REPORT* ]]; then
        # 同步事件到来时，将所有累积的事件一次发送
        if [[ $dx -ne 0 || $dy -ne 0 || ${#events[@]} -gt 0 ]]; then
            all=()
            # 相对位移事件
            [ $dx -ne 0 ] && all+=('{"type":"rel","data":{"axis":"x","value":'$dx'}}')
            [ $dy -ne 0 ] && all+=('{"type":"rel","data":{"axis":"y","value":'$dy'}}')
            # 合并按键/滚轮事件
            all+=("${events[@]}")
            # 用 IFS 拼接 JSON 数组，直接输出到 QMP 连接
            IFS=','; printf '{"execute":"input-send-event","arguments":{"events":[%s]}}\n' "${all[*]}" >&3
            # 重置累积状态
            dx=0 dy=0 events=()
        fi
    fi
done


