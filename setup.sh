#!/bin/sh

# Install XFCE GUI, VNC server, and other necessary packages

apk add --no-cache ca-certificates bash curl jq openssl sudo xvfb x11vnc xfce4 xfce4-terminal faenza-icon-theme bash procps nano git pciutils gzip p7zip cpio tar unzip xarchiver ethtool \
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

# Check Alpine Linux version with cat /etc/*release*  and  cat /etc/issue
# Check QEMU version with /usr/bin/qemu-system-x86_64 --version
# Check libvirt version with virsh version --daemon  or libvirtd --version

# Replace OVMF UEFI firmware file included in stable QEMU 8.1.3 with newer version to fix the issue of Windows 11 not booting and getting stuck at TianoCore logo
# You can see all firmware files from the main branch on the link below or select a specific branch / tag release version
# https://gitlab.com/qemu-project/qemu/-/tree/master/pc-bios
rm /usr/share/qemu/edk2-x86_64-secure-code.fd
wget https://gitlab.com/qemu-project/qemu/-/raw/v8.2.0-rc3/pc-bios/edk2-x86_64-secure-code.fd.bz2 -P /usr/share/qemu
bzip2 -d /usr/share/qemu/edk2-x86_64-secure-code.fd.bz2


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
# Alternative with xdg-settings command:
# xdg-settings set default-web-browser firefox.desktop

mkdir -p ~/.config/xfce4

cat <<-EOF > ~/.config/xfce4/helpers.rc
WebBrowser=custom-WebBrowser
EOF

mkdir -p ~/.local/share/xfce4/helpers

cat <<-EOF > ~/.local/share/xfce4/helpers/custom-WebBrowser.desktop
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

clear

# Network Interface PCI information

#IFS=$'\n'
METADATA=$(curl -s metadata.packet.net/metadata)
INTERFACES_COUNT=$(echo $METADATA | jq '.network.interfaces | length')
echo
echo "Network interfaces:"
echo

for i in $(seq 1 $INTERFACES_COUNT)
do

METADATA_MAC=$(echo $METADATA | jq -r .network.interfaces[$i-1].mac)
METADATA_IF_NAME=$(echo $METADATA | jq -r .network.interfaces[$i-1].name)

for LINE in $(ls -d /sys/class/net/*/ | cut -d '/' -f5)
do

#LOCAL_MAC=$(cat /sys/class/net/$LINE/address)
# /sys/class/net/$LINE/address returns the same MAC for any interface part of a bonded interfaces so it's not reliable
# ethtool permanent address option returns the real MAC of the interface regardless if it's part of a bond
LOCAL_MAC=$(ethtool -P $LINE | cut -d ' ' -f3)

# some interfaces like bonds will have the same MAC address as the primary interface but they won't have a uevent file so we're ignoring it
if [ "$METADATA_MAC" == "$LOCAL_MAC" ] && [ -f "/sys/class/net/$LINE/device/uevent" ]; then

    PCI_ID=$(grep PCI_SLOT_NAME /sys/class/net/$LINE/device/uevent | cut -d "=" -f2)

# only add API Interface name if OS name is different

    if [ "$METADATA_IF_NAME" == "$LINE" ]; then
        lspci -D | grep $PCI_ID | sed 's#^#PCI BDF #' | sed "s/$/ ($LINE)/"
    else
        lspci -D | grep $PCI_ID | sed 's#^#PCI BDF #' | sed "s/$/ ($LINE)/" | sed "s/$/ ($METADATA_IF_NAME)/"
    fi

    echo
    break
fi
done
done


# Storage drive information and PCI mapping

IFS=$'\n'
echo
echo "Local storage drives:"
echo

#SATA drives
for LINE in $(ls -l /sys/block/ | grep "sd" | awk '{print $9, $10, $11}')
do

PCI_ID=$(echo $LINE | cut -d "/" -f4)
lspci -D | grep $PCI_ID | sed 's#^#PCI BDF #'
DEVICE_PATH=$(echo $LINE | awk '{print $1}' | sed 's#^#/dev/#')
lsblk -p -o NAME,TYPE,SIZE,MODEL,TRAN,ROTA,HCTL,MOUNTPOINT $DEVICE_PATH | sed 's#NAME#PATH#' | sed 's#ROTA#DRIVE-TYPE#' | sed 's# 0 #SSD      #' | sed 's# 1 #HDD      #'
echo

done

#NVMe drives
for LINE in $(ls -l /sys/block/ | grep "nvme" | awk '{print $9, $10, $11}')
do

PCI_ID=$(echo $LINE | cut -d "/" -f5)
lspci -D | grep $PCI_ID | sed 's#^#PCI BDF #'
DEVICE_PATH=$(echo $LINE | awk '{print $1}' | sed 's#^#/dev/#')
lsblk -p -o NAME,TYPE,SIZE,MODEL,TRAN,ROTA,HCTL,MOUNTPOINT $DEVICE_PATH | sed 's#NAME#PATH#' | sed 's#ROTA#DRIVE-TYPE#' | sed 's# 0 #SSD      #' | sed 's# 1 #HDD      #'
echo

done

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
