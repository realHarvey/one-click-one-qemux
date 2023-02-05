#!/bin/bash

echo "=========== UBUNTU SOFTWARE SOURCE CHANGING ============>"

read -p "请选择更新到清华源 [y/n]" input
case $input in
        [yY]* | "")
                source /etc/os-release
                case $VERSION_ID in
                        "18.04")
                                sudo rm /etc/apt/sources.list
                                sudo cp 18_sources.list /etc/apt/
                                sudo mv /etc/apt/18_sources.list /etc/apt/sources.list
                                ;;
                        "20.04")
                                sudo rm /etc/apt/sources.list
                                sudo cp 20_sources.list /etc/apt/
                                sudo mv /etc/apt/20_sources.list /etc/apt/sources.list
                                ;;
                        "22.04")
                                sudo rm /etc/apt/sources.list
                                sudo cp 22_sources.list /etc/apt/
                                sudo mv /etc/apt/22_sources.list /etc/apt/sources.list
                                ;;
                        *)
                                echo " 您的linux不是预期版本, 请使用ubuntu 18.04 ~ 22.04"
                                exit
                                ;;
                esac
                ;;
        [nN]* | *)
                echo "未选择更新到清华源 !"
                ;;        
esac

sudo apt update
sudo apt upgrade


echo "=========== COMPILE ENVIRONMENT INITALIZING ============>"

# c/c++ 环境
sudo apt install build-essential
sudo apt install cmake
sudo apt install gdb
sudo apt install lldb
sudo apt install clang
sudo apt install clangd # 18.04源中没有
sudo apt install clang-tidy
sudo apt install gcc-arm-none-eabi
sudo apt install gcc-arm-linux-gnueabihf
sudo apt install gcc-arm-linux-gnueabi
sudo apt install bear

#python环境
read -p "python : 是否更新到3.11版 [y/n]" input
case $input in
        [yY]* | "")
                sudo add-apt-repository ppa:deadsnakes/ppa
                sudo apt install python3.11
                ;;
        [nN]* | *)
                echo "未选择更新到3.11"
                ;;
esac

# QEMU 环境
sudo apt install flex bison libncurses-dev libelf-dev libssl-dev u-boot-tools bc xz-utils fakeroot pkg-config ninja-build

sudo apt-cache search pixman
sudo apt install libpixman-1-dev

read -p  "qemu : 选择默认版本v4.2 [y] || 慢慢编译v7.2 [n]" input
case $input in
        [yY]* | "")
                # 选择软件源中的qemu - v4
                sudo apt install qemu-system
                ;;
        [nN]*)
                # 自由选择qemu版本
                wget https://download.qemu.org/qemu-7.2.0.tar.xz
                tar xvJf qemu-7.2.0.tar.xz
                cd qemu-7.2.0
                ./configure
                make
                sudo make install
                ;;
        *)
                echo "不下载你玩个毛"
                cd ~
                rm -rf one-click-one-qemux
                exit  
                ;;      
esac

echo "=========== COMPILE LINUX KERNEL ============>"

cd /home
sudo mkdir qemux
sudo chmod 777 qemux
cd qemux
mkdir kernel
cd kernel
wget https://mirrors.tuna.tsinghua.edu.cn/kernel/v5.x/linux-5.10.99.tar.xz
tar -xvf linux-5.10.99.tar.xz
cd linux-5.10.99
sed -i '370d' Makefile
sed -i '370a ARCH ?= arm\n CROSS_COMPILE = arm-linux-gnueabi-' Makefile # 注意修改arch时不要有空格

make vexpress_defconfig

# 依据核心数调配编译线程, 默认4核8线程
make zImage  -j8
make modules -j8
make dtbs    -j8
make LOADADDR=0x60003000 uImage  -j8

cp arch/arm/boot/zImage /home/qemux/
cp arch/arm/boot/uImage /home/qemux/
cp arch/arm/boot/dts/vexpress-v2p-ca9.dtb /home/qemux/

cd /home/qemux
touch start.sh
chmod 777 start.sh
echo " " >> start.sh
sed -i '1a qemu-system-arm \\\
        -M vexpress-a9 \\\
        -m 512M \\\
        -kernel zImage \\\
        -dtb vexpress-v2p-ca9.dtb \\\
        -nographic \\\
        -append "console=ttyAMA0"' start.sh

echo "=========== MAKE ROOT FILE SYSTEM ============>"

cd /home/qemux
mkdir filesys
cd filesys
wget https://busybox.net/downloads/busybox-1.35.0.tar.bz2
tar -xvf busybox-1.35.0.tar.bz2
cd busybox-1.35.0
sudo mkdir -p /home/nfs
sudo chmod 777 /home/nfs/

sed -i '190d' Makefile
sed -i '190a ARCH ?= arm \n CROSS_COMPILE = arm-linux-gnueabi-' Makefile

echo " 正在加载菜单... "
echo " [y/n]选取 Settings —-> [*] vi-style line editing commands (New) "
echo " 更改 Settings —-> Destination path for 'make install' 为 /home/nfs "

read -p "记住之后请回车确认" input
case $input in
        *) ;;
esac
echo "按错了不要慌, 请去github中查看README"
sleep 3

make menuconfig

# 编译安装
make install -j8

# 动态链接库
cd /home/nfs
mkdir lib
cd /usr/arm-linux-gnueabi/lib
cp *.so* /home/nfs/lib -d

# 设备节点
cd /home/nfs
mkdir dev
cd dev
sudo mknod -m 666 tty1 c 4 1
sudo mknod -m 666 tty2 c 4 2
sudo mknod -m 666 tty3 c 4 3
sudo mknod -m 666 tty4 c 4 4
sudo mknod -m 666 console c 5 1
sudo mknod -m 666 null c 1 3

# 初始化进程
cd /home/nfs
mkdir -p etc/init.d
cd etc/init.d
touch rcS
chmod 777 rcS
echo " " >> rcS
sed -i '1a #!/bin/sh \n
PATH=/bin:/sbin:/usr/bin:/usr/sbin \n
export LD_LIBRARY_PATH=/lib:/usr/lib \n
/bin/mount -n -t ramfs ramfs /var \n
/bin/mount -n -t ramfs ramfs /tmp \n
/bin/mount -n -t sysfs none /sys \n
/bin/mount -n -t ramfs none /dev \n
/bin/mkdir /var/tmp \n
/bin/mkdir /var/modules \n
/bin/mkdir /var/run \n
/bin/mkdir /var/log \n
/bin/mkdir -p /dev/pts \n
/bin/mkdir -p /dev/shm \n
/sbin/mdev -s \n
/bin/mount -a \n
echo "-------------------------------------" \n
echo "==== vexpress board initalizing ====>" \n
echo "-------------------------------------" ' rcS

# 设置文件系统
cd /home/nfs/etc
touch fstab
echo " " >> fstab
sed -i '1a proc    /proc           proc    defaults        0       0 \n
none    /dev/pts        devpts  mode=0622       0       0 \n
mdev    /dev            ramfs   defaults        0       0 \n
sysfs   /sys            sysfs   defaults        0       0 \n
tmpfs   /dev/shm        tmpfs   defaults        0       0 \n
tmpfs   /dev            tmpfs   defaults        0       0 \n
tmpfs   /mnt            tmpfs   defaults        0       0 \n
var     /dev            tmpfs   defaults        0       0 \n
ramfs   /dev            ramfs   defaults        0       0 ' fstab

# 初始化脚本
cd /home/nfs/etc
touch inittab
echo " " >> inittab
sed -i '1a ::sysinit:/etc/init.d/rcS \n
::askfirst:-/bin/sh \n
::ctrlaltdel:/bin/umount -a -r' inittab

# 环境变量
cd /home/nfs/etc
touch profile
echo " " >> profile
sed -i '1a USER="root" \n
LOGNAME=$USER \n
export HOSTNAME="cat /etc/sysconfig/HOSTNAME" \n
export USER=root \n
export HOME=/root \n
export PS1="[$USER@$HOSTNAME \\\W]\\\# " \n
PATH=/bin:/sbin:/usr/bin:/usr/sbin \n
LD_LIBRARY_PATH=/lib:/usr/lib:$LD_LIBRARY_PATH \n
export PATH LD_LIBRARY_PATH' profile

# 主机名
cd /home/nfs/etc
mkdir sysconfig
cd sysconfig
echo "vexpress" >>  HOSTNAME

# 其他dirs
cd /home/nfs
mkdir mnt proc root sys tmp var

# 封装root并挂载
cd /home/
sudo mkdir temp
sudo dd if=/dev/zero of=rootfs.ext3 bs=1M count=32
sudo mkfs.ext3 rootfs.ext3
sudo mount -t ext3 rootfs.ext3 temp/ -o loop
sudo cp -r nfs/* temp/
sudo umount temp
sudo mv rootfs.ext3 qemux
cd /home/qemux
echo " " >> start.sh
sudo sed -i '1a qemu-system-arm \\\
        -M vexpress-a9 \\\
        -m 512M \\\
        -kernel zImage \\\
        -dtb vexpress-v2p-ca9.dtb \\\
        -nographic \\\
        -append "root=/dev/mmcblk0 rw console=ttyAMA0" \\\
        -sd rootfs.ext3' start.sh

echo "=========== new lab environment is built ============>"	
