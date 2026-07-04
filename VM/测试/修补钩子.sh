#!/bin/bash


#启动??内核版本<RDTSC>
#新的<内核RDTSC已修改>=1	老的<内核RDTSC未修改>=3

#虚拟机名称
#VMos=名称=XML  <name>???</name>

#关闭虚拟机之后-加载GPU驱动程序<Load>
#是=1	否=3


RDTSC=1

VMos=win10

Load=1

#立即启动系统<GRUB引导菜单 停留的秒数>
TIMEOUT=0


## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ##

# 定义颜色变量
YELLOW='\e[1;33m' # 黄
GREEN='\e[1;32m' # 绿
PINK='\e[1;35m' # 粉红
RES='\e[0m' # 清除颜色


if [ $RDTSC == 1 ]; then echo_RDTSC="$GREEN新的<内核RDTSC已修改>$RES" ;else echo_RDTSC="$PINK老的<内核RDTSC未修改>$RES" ;fi
if [ $Load == 1 ]; then echo_Load="$GREEN是$RES" ;else echo_Load="$PINK否$RES" ;fi

echo -e "\n	启动内核:$echo_RDTSC\n	虚拟机名称 :$YELLOW$VMos$RES\n	关闭虚拟机之后-加载GPU驱动程序:$echo_Load\n	停留的秒数 :$GREEN$TIMEOUT$RES\n"
if [[ $EUID -ne 0 ]]; then echo -e "	用户权限不够,root用户执行\n" 1>&2;exit 1;fi



#修改虚拟机名称 
sed -i "s/if \[\[ \$OBJECT == .*/if \[\[ \$OBJECT == \"$VMos\" ]]; then/g"   /etc/libvirt/hooks/qemu


#修改是否加载GPU驱动程序
my_array=("drm" "drm_kms_helper" "i2c_nvidia_gpu" "nvidia" "nvidia_modeset" "nvidia_drm" "nvidia_uvm" "amdgpu" "radeon")
for item in "${my_array[@]}"; do
if [ $Load == 1 ]; then	sed -i "s/#modprobe/modprobe/g"   /bin/vfio-teardown.sh 
else	sed -i -e "s/modprobe $item/#modprobe $item/g" -e "s/##/#/g"	/bin/vfio-teardown.sh	;fi
done



#修改启动内核版本
if [ $RDTSC == 1 ]; then	RDTSC_CH="0"	;else	RDTSC_CH='"1>2"'	;fi
sed -i "s/GRUB_DEFAULT=.*/GRUB_DEFAULT=$RDTSC_CH/g" /etc/default/grub

#立即启动系统<GRUB引导菜单 停留的秒数>
sed -i "s/GRUB_TIMEOUT=.*/GRUB_TIMEOUT=$TIMEOUT/g" /etc/default/grub


update-grub


