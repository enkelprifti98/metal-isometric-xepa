#!/bin/sh

# Install XFCE GUI, VNC server, and other necessary packages

apk add --no-cache ca-certificates bash curl jq openssl sudo xvfb x11vnc xfce4 xfce4-terminal faenza-icon-theme bash procps nano git pciutils gzip p7zip cpio tar unzip xarchiver \
--update \
--repository=http://dl-cdn.alpinelinux.org/alpine/edge/testing/ \
--repository=http://dl-cdn.alpinelinux.org/alpine/edge/community/ \
--repository=http://dl-cdn.alpinelinux.org/alpine/edge/main/


#Xfce usually stores its configuration files in ~/.config/xfce4 (as well as ~/.local/share/xfce4 and ~/.config/Thunar).
#Keyboard shortcuts are stored in ~/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-keyboard-shortcuts.xml.
#There's a global default set of configuration files in /etc/xdg/xfce4, /etc/xdg/Thunar/, /etc/xdg/menus, etc. (as well as /etc/xdg/xdg-xubuntu if you're using Xubuntu).


# Set VNC password: ("admin" but you can set it to whatever)

mkdir -p /root/.vnc && x11vnc -storepasswd admin /root/.vnc/passwd

# Start GUI and VNC server services

export DISPLAY=:99
export RESOLUTION=1920x1080x24

nohup /usr/bin/Xvfb :99 -screen 0 $RESOLUTION -ac +extension GLX +render -noreset > /dev/null 2>&1 &

nohup startxfce4 > /dev/null 2>&1 &

nohup x11vnc -xkb -noxrecord -noxfixes -noxdamage -display $DISPLAY -forever -bg -rfbauth /root/.vnc/passwd -users root -rfbport 5900 > /dev/null 2>&1 &

# This network config file with a loopback interface is needed for libvirtd and noVNC (loopback) services to start successfully

cat > /etc/network/interfaces <<EOF
auto lo
iface lo inet loopback
EOF

# Fallback to cgroup v1 by unmounting cgroup v2 since the Rescue OS Alpine Linux build has v2 enabled by default.
# Without unmounting cgroup v2, qemu will throw an error when starting a VM.

umount /sys/fs/cgroup

# Install KVM hypervisor

apk add libvirt-daemon qemu-img qemu-system-x86_64 qemu-modules virt-manager \
--update \
--repository=http://dl-cdn.alpinelinux.org/alpine/edge/testing/ \
--repository=http://dl-cdn.alpinelinux.org/alpine/edge/community/ \
--repository=http://dl-cdn.alpinelinux.org/alpine/edge/main/

rc-update add libvirtd
modprobe tun
modprobe br_netfilter
grep -q -E 'vmx' /proc/cpuinfo && modprobe kvm-intel
grep -q -E 'svm' /proc/cpuinfo && modprobe kvm-amd

# Enable VFIO PCI Passthrough

modprobe vfio_pci
modprobe vfio_iommu_type1
chown qemu /dev/vfio/vfio

# Install software TPM package for emulating TPM modules
# (the package location seems to shift between the different Alpine repos/branches sometimes, you can check the latest-stable and edge repos at http://dl-cdn.alpinelinux.org/alpine/ )

apk add swtpm libtpms --update --repository=http://dl-cdn.alpinelinux.org/alpine/edge/testing/ --repository=http://dl-cdn.alpinelinux.org/alpine/edge/community/ --repository=http://dl-cdn.alpinelinux.org/alpine/edge/main/

# Start libvirtd service

rc-service libvirtd start

# Install web-browser (Firefox works, Chromium seems to throw an I/O error and doesn't launch)

apk add firefox-esr \
--update \
--repository=http://dl-cdn.alpinelinux.org/alpine/edge/testing/ \
--repository=http://dl-cdn.alpinelinux.org/alpine/edge/community/ \
--repository=http://dl-cdn.alpinelinux.org/alpine/edge/main/

# Set Firefox as the default Web Browser since recent installations don't automatically set it as the default

cat <<-EOF >> ~/.config/xfce4/helpers.rc
WebBrowser=custom-WebBrowser
EOF

cat <<-EOF >> ~/.local/share/xfce4/helpers/custom-WebBrowser.desktop
[Desktop Entry]
NoDisplay=true
Version=1.0
Encoding=UTF-8
Type=X-XFCE-Helper
X-XFCE-Category=WebBrowser
X-XFCE-CommandsWithParameter=firefox-esr "%s"
Icon=firefox-esr
Name=firefox-esr
X-XFCE-Commands=firefox-esr
EOF

# Install NoVNC (VNC client over http)

export NOVNC_TAG=$(curl -s https://api.github.com/repos/novnc/noVNC/releases/latest | jq -r .tag_name)

export WEBSOCKIFY_TAG=$(curl -s https://api.github.com/repos/novnc/websockify/releases/latest | jq -r .tag_name)

git clone --depth 1 https://github.com/novnc/noVNC --branch ${NOVNC_TAG} /root/noVNC

git clone --depth 1 https://github.com/novnc/websockify --branch ${WEBSOCKIFY_TAG} /root/noVNC/utils/websockify

cp /root/noVNC/vnc.html /root/noVNC/index.html

sed -i "s/UI.initSetting('resize', 'off');/UI.initSetting('resize', 'scale');/" /root/noVNC/app/ui.js

nohup /root/noVNC/utils/novnc_proxy --vnc localhost:5900 --listen 80 > /dev/null 2>&1 &

# Install File Browser (https://filebrowser.org/)
# Default login is:
# Username: admin
# Password: admin

curl -fsSL https://raw.githubusercontent.com/filebrowser/get/master/get.sh | bash

PUBLIC_IP=$(curl -s https://metadata.platformequinix.com/metadata | jq -r ".network.addresses[] | select(.public == true) | select(.address_family == 4) | .address")

nohup filebrowser -r /root -a $PUBLIC_IP -p 8080 > /dev/null 2>&1 &

mkdir /root/Downloads

printf "\n\n"
echo "The ISO installation environment is available at:"
printf "\n"
echo "http://$PUBLIC_IP/"
printf "\n"
echo "The File Transfer portal is available at:"
printf "\n"
echo "http://$PUBLIC_IP:8080/"
printf "\n"
echo "The instance is running in $([ -d /sys/firmware/efi ] && echo UEFI || echo BIOS) boot mode."
printf "\n\n"
