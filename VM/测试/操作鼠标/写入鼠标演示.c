#include <stdio.h>
#include <stdlib.h>
#include <fcntl.h>
#include <unistd.h>
#include <linux/input.h>
#include <string.h>
#include <errno.h>

int main() {
    const char *device = "/dev/input/by-id/usb-E-Signal_USB_Gaming_Mouse-event-mouse";
    int fd = open(device, O_WRONLY);
    if (fd < 0) {
        perror("open");
        return 1;
    }

    struct input_event ev;
    memset(&ev, 0, sizeof(ev));

    // 模拟相对移动：向右移动300，向下移动500
    // X 轴相对移动
    ev.type = EV_REL;
    ev.code = REL_X;
    ev.value = 300;
    if (write(fd, &ev, sizeof(ev)) != sizeof(ev)) {
        perror("write REL_X");
    }

    // Y 轴相对移动
    ev.code = REL_Y;
    ev.value = 500;
    if (write(fd, &ev, sizeof(ev)) != sizeof(ev)) {
        perror("write REL_Y");
    }

    // 同步事件，通知接收方一个完整的事件包结束
    ev.type = EV_SYN;
    ev.code = SYN_REPORT;
    ev.value = 0;
    if (write(fd, &ev, sizeof(ev)) != sizeof(ev)) {
        perror("write SYN_REPORT");
    }

    close(fd);
    return 0;
}

