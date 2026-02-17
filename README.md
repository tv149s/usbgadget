Raspberry Pi 4 Model B
从默认系统到完整 USB Gadget（三合一）实战工程记录

项目地址：
https://github.com/tv149s/usbgadget

一、项目背景与目标
目标

将 Raspberry Pi 4 Model B 改造为完整 USB Gadget 设备，实现：

✅ HID Keyboard

✅ HID Mouse

✅ CDC ACM Serial

✅ UVC Camera

目标状态：

Windows 主机可稳定枚举全部功能

UVC 视频可持续输出

HID 与 ACM 可长期稳定运行

系统可自动启动并可调试

二、系统架构总览
整体架构
                Windows Host
                       │
                USB High Speed
                       │
              ┌────────────────┐
              │  Pi 4 USB OTG  │
              └────────────────┘
                       │
                 dwc2 (UDC)
                       │
               libcomposite
                       │
     ┌──────────┬───────────┬──────────┐
     │   HID    │    ACM    │    UVC   │
     │ function │  function │ function │
     └──────────┴───────────┴──────────┘
                              │
                      uvc-gadget (userspace)
                              │
                       v4l2 source pipeline

关键组件说明
1️⃣ dwc2（USB Device Controller）

负责：

将 Pi 4 USB-C 控制器置于 peripheral 模式

提供 UDC 设备接口

2️⃣ libcomposite

提供：

USB Function 构建框架

描述符配置

endpoint 分配

3️⃣ HID / ACM

内核 Function
不需要用户态参与。

4️⃣ UVC

分为两部分：

内核 UVC Function（描述符 + endpoint）

用户态 uvc-gadget（真正写入视频流）

⚠ Kernel UVC 只负责枚举，不负责流。

三、开发阶段实战过程
Step 1：确认硬件与内核基线

目标：

确保处于已验证可工作的内核版本。

基线：

Linux 6.12.62+rpt-rpi-v8


为什么重要：

USB Gadget 高度依赖：

dwc2

libcomposite

UVC 内核实现

不同内核版本可能：

UDC 不出现

UVC 不稳定

枚举异常

验证：

ls /sys/class/udc


应出现：

fe980000.usb

Step 2：启用 USB Peripheral 模式

修改：

/boot/firmware/config.txt
dtoverlay=dwc2,dr_mode=peripheral

/boot/firmware/cmdline.txt
modules-load=dwc2,libcomposite


重启后验证：

ls /sys/class/udc

常见问题
❌ config.txt 被改回 host

原因：

cloud-init

其他系统脚本覆盖

解决：

审计文件改写

禁用自动重写源

Step 3：部署 Gadget 脚本结构

核心脚本：

usb-gadget.sh

usb-gadget-stream.sh

usb-gadget-source.sh

配置文件：

usb-gadget.default

usb-gadget-video-formats.conf

工程原则：

所有功能开关配置化

UVC 格式单独文件

可 A/B 切换

Step 4：分层启用（HID + ACM 先行）

第一阶段：

ENABLE_UVC=0


仅验证：

/dev/hidg0

/dev/hidg1

/dev/ttyGS0

在 Windows 应看到：

USB HID Device

USB Serial Device

若出现 Unknown USB Device：

检查 UDC 绑定

检查描述符创建顺序

Step 5：启用 UVC（保守模式）

启用 UVC 但仅保留：

640x480
YUYV
单一分辨率
maxpacket=1024
interval=1


目的：

避免 descriptor 复杂度导致枚举失败。

Step 6：脱离 UVC 验证视频源

使用：

v4l2loopback
ffmpeg testsrc


验证：

源稳定

格式固定

不发生 format 漂移

启用：

exclusive_caps=1
keep_format=1

Step 7：接入 uvc-gadget

关键：

必须使用正确参数：

uvc-gadget -u <uvc_out> -v <source>


错误参数会导致：

枚举成功但无流

直接 stream 失败

Step 8：源切换与稳定性测试

引入：

testsrc profile

USB 摄像头 profile

低帧率 profile (15fps)

目的：

定位冻结与高负载问题。

Step 9：-61 风暴与带宽分析（核心难点）
现象

内核日志：

VS request completed with status -61


流打开即关闭。

根因

UVC 使用 Isochronous 传输。

High Speed 理论最大等时带宽：

约 24 MB/s

计算：

640×480×2 bytes × 30fps ≈ 18.4 MB/s

再考虑：

USB 协议开销

endpoint 分配

其他 function 占用

实际可用带宽更低。

结果：

主机拒绝流。

解决方案

1️⃣ 降帧率

10–15 fps


2️⃣ 改 MJPEG

MJPEG 带宽远低于 YUYV。

3️⃣ 降分辨率

Step 10：usbmon 自动抓包体系

目标：

在异常瞬间保留：

内核日志

usbmon 抓包

原因：

系统可能冻结

日志窗口可能丢失

方案：

后台持续抓取

触发式保存

Step 11：最终稳定状态验证

完整状态应满足：

/sys/class/udc 有 fe980000.usb
/dev/hidg0
/dev/hidg1
/dev/ttyGS0
UVC 正常出流
systemd service active


Windows 可看到：

HID Keyboard

HID Mouse

USB Serial

USB Camera

四、关键工程经验总结
1️⃣ 永远分层验证

不要三合一一起调。

2️⃣ UVC 不是“分辨率问题”，是带宽问题

必须算带宽。

3️⃣ 内核 function ≠ 用户态流

UVC 需要 userspace 参与。

4️⃣ 先验证源，再接入 Gadget

不要在两层同时调试。

五、最终成果

实现：

完整 USB 复合设备

三种功能稳定并存

自动启动

可调试体系

这已不是“玩具项目”。

这是一个完整的 USB 设备工程实现。
