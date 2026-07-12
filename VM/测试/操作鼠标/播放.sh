#!/bin/bash

# 同时按住左键+侧键播放宏，松开任一停止

#找鼠标	cat /proc/bus/input/devices | grep -B5 mouse
#找鼠标	ls -l /dev/input/by-id/

## 运行后台	nohup bash '/home/user/桌面/播放.sh' & nohup bash '/home/user/桌面/录制.sh' &
## 杀死后台运行	pkill -f 录制.sh && pkill -f 播放.sh

MACRO_FILE="/home/user/macro.evemu"
MOUSE_EVENT="/dev/input/by-id/usb-E-Signal_USB_Gaming_Mouse-event-mouse"



# 只保留包含这两个按键的行，过滤掉大量移动/滚轮事件，减少循环开销
stdbuf -oL evtest "$MOUSE_EVENT" 2>&1 | grep --line-buffered -E "BTN_LEFT|BTN_SIDE" | while IFS= read -r line; do
    # 更新按键状态
    case "$line" in
        *"BTN_LEFT"*)
            [[ $line == *"value 1"* ]] && left=1 || left=0 ;;
        *"BTN_SIDE"*)
            [[ $line == *"value 1"* ]] && side=1 || side=0 ;;
    esac

    # 两键同时按下 -> 启动回放
    if [[ ${left:-0} -eq 1 && ${side:-0} -eq 1 ]]; then
        if [[ -z "$PLAY_PID" ]] || ! kill -0 "$PLAY_PID" 2>/dev/null; then
            echo "播放"
            evemu-play "$MOUSE_EVENT" < "$MACRO_FILE" &
            PLAY_PID=$!
        fi
    # 任一释放 -> 停止回放
    elif [[ -n "$PLAY_PID" ]] && kill -0 "$PLAY_PID" 2>/dev/null; then
        echo "停止"
        kill -9 "$PLAY_PID" 2>/dev/null
        wait "$PLAY_PID" 2>/dev/null
        PLAY_PID=""
    fi
done

