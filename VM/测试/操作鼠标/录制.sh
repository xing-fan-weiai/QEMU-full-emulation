#!/bin/bash

# 录制鼠标操作，松开按键停止录制

#找鼠标	cat /proc/bus/input/devices | grep -B5 mouse
#找鼠标	ls -l /dev/input/by-id/

## 运行后台	nohup bash '/home/user/桌面/播放.sh' & nohup bash '/home/user/桌面/录制.sh' &
## 杀死后台运行	pkill -f 录制.sh && pkill -f 播放.sh

MACRO_FILE="/home/user/macro.evemu"
MOUSE_OT="/dev/input/by-id/usb-E-Signal_USB_Gaming_Mouse-event-mouse"		#实际录制操作的鼠标

MOUSE_EVENT="/dev/input/by-id/usb-0000_USB_OPTICAL_MOUSE-event-mouse"		#监听按键启用录制的鼠标
SIDE_BUTTON="BTN_MIDDLE"



echo "按住 $SIDE_BUTTON 开始录制，松开立即停止..."

# 实时监听按键事件
stdbuf -oL evtest "$MOUSE_EVENT" 2>&1 | grep --line-buffered "$SIDE_BUTTON" | while IFS= read -r line; do
    # 按键按下 (value 1) → 启动录制
    if [[ $line == *"value 1"* ]]; then
        if [[ -z "$REC_PID" ]] || ! kill -0 "$REC_PID" 2>/dev/null; then
            echo "● 录制中..."
            evemu-record "$MOUSE_OT" > "$MACRO_FILE" &
            REC_PID=$!
        fi

    # 按键松开 (value 0) → 停止录制
    elif [[ $line == *"value 0"* ]]; then
        if [[ -n "$REC_PID" ]] && kill -0 "$REC_PID" 2>/dev/null; then
            echo "■ 录制停止"
            kill -9 "$REC_PID" 2>/dev/null
            wait "$REC_PID" 2>/dev/null
            REC_PID=""
        fi
    fi
done

