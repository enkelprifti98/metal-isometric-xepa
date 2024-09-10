#!/bin/sh

# Run from Out-of-Band console
# wget -q -O setup-v2.sh https://raw.githubusercontent.com/enkelprifti98/metal-isometric-xepa/main/setup-v2.sh && chmod +x setup-v2.sh && ./setup-v2.sh

#echo $1  (first argument)
#echo $2  (second argument)
#echo $*  ($* is a single string, whereas $@ is an actual array)
#echo $@

if [[ "$*" == *"--restart"* ]]; then
    #echo "argument exists"

    echo "Restarting XEPA services..."

    rc-service dbus stop
    rc-service dbus start

    rc-service libvirtd stop
    rc-service libvirtd start

    export DISPLAY=:99
    export RESOLUTION=1920x1080x24

    while pkill -f "/usr/bin/Xvfb $DISPLAY -screen 0 $RESOLUTION -ac +extension GLX +render -noreset"; do
        sleep 1
    done
    nohup /usr/bin/Xvfb $DISPLAY -screen 0 $RESOLUTION -ac +extension GLX +render -noreset > /dev/null 2>&1 &

    #xfce4-session-logout --halt
    while pkill -f "/usr/bin/dbus-launch --sh-syntax --exit-with-session xfce4-session"; do
        sleep 1
    done
    nohup startxfce4 > /dev/null 2>&1 &

    while pkill -f "x11vnc -xkb -noxrecord -noxfixes -noxdamage -display $DISPLAY -forever -bg -rfbauth /root/.vnc/passwd -users root -rfbport 5900"; do
        sleep 1
    done
    nohup x11vnc -xkb -noxrecord -noxfixes -noxdamage -display $DISPLAY -forever -bg -rfbauth /root/.vnc/passwd -users root -rfbport 5900 > /dev/null 2>&1 &

    while pkill -f "bash /root/noVNC/utils/novnc_proxy --vnc localhost:5900 --listen 80"; do
        sleep 1
    done
    nohup /root/noVNC/utils/novnc_proxy --vnc localhost:5900 --listen 80 > /dev/null 2>&1 &

    while pkill -f "filebrowser -r /root -a 0.0.0.0 -p 8080"; do
        sleep 1
    done
    nohup filebrowser -r /root -a 0.0.0.0 -p 8080 > /dev/null 2>&1 &

    echo "Done."

    exit

#else
    #echo "argument doesn't exist"
fi

echo
echo "XEPA ISO INSTALLATION ENVIRONMENT"
echo

# Check for internet connectivity
wget -q --spider http://google.com

if [ $? -ne 0 ]; then
    echo
    echo "Server has no internet connectivity, try again."
    echo
    exit
fi

# Check for metadata service availability
METADATA=$(curl -s metadata.packet.net/metadata)
if (echo $METADATA | jq .message | grep -Eo "resource not found" > /dev/null); then
    echo
    echo "Metadata service isn't available. Try again."
    echo
    exit
fi

env | grep METAL_AUTH_TOKEN > /dev/null
if [ $? -eq 0 ]; then
  echo "Reading Equinix Metal API key from METAL_AUTH_TOKEN environment variable"
  AUTH_TOKEN=$METAL_AUTH_TOKEN
else
  read -p "Enter Equinix Metal API Key: " AUTH_TOKEN
fi

OUTPUT=$(curl -s "https://api.equinix.com/metal/v1/user/api-keys" \
        -X GET \
        -H "X-Auth-Token: $AUTH_TOKEN")
sleep 1
if (echo $OUTPUT | jq -e 'has("error")' > /dev/null); then
        echo $OUTPUT | jq
        exit
fi


# Remove edge branch repos because newer packages can cause issues
# You can check package versions from specific branches and repos here:
# https://pkgs.alpinelinux.org/packages
# The actual repository links with package files are hosted here:
# https://dl-cdn.alpinelinux.org/alpine/
sed -i '/edge/d' /etc/apk/repositories

# Install XFCE GUI, VNC server, and other necessary packages
# The standard gtk+3.0 required package seems to fail, installing gtk+3.0-dev works so startxfce4 runs successfully.

apk add --no-cache ca-certificates bash curl jq openssl sudo xvfb x11vnc xfce4 xfce4-terminal faenza-icon-theme bash procps nano git pciutils lshw gparted gzip p7zip cpio tar unzip xarchiver ethtool mokutil gtk+3.0-dev \
--update

rc-service dbus start

#Xfce usually stores its configuration files in ~/.config/xfce4 (as well as ~/.local/share/xfce4 and ~/.config/Thunar).
#Keyboard shortcuts are stored in ~/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-keyboard-shortcuts.xml.
#There's a global default set of configuration files in /etc/xdg/xfce4, /etc/xdg/Thunar/, /etc/xdg/menus, etc. (as well as /etc/xdg/xdg-xubuntu if you're using Xubuntu).


# Set VNC password: ("admin" but you can set it to whatever)

mkdir -p /root/.vnc && x11vnc -storepasswd admin /root/.vnc/passwd

# Start GUI and VNC server services

export DISPLAY=:99
export RESOLUTION=1920x1080x24

nohup /usr/bin/Xvfb $DISPLAY -screen 0 $RESOLUTION -ac +extension GLX +render -noreset > /dev/null 2>&1 &

nohup startxfce4 > /dev/null 2>&1 &

nohup x11vnc -xkb -noxrecord -noxfixes -noxdamage -display $DISPLAY -forever -bg -rfbauth /root/.vnc/passwd -users root -rfbport 5900 > /dev/null 2>&1 &

# This network config file with a loopback interface is needed for libvirtd and noVNC (loopback) services to start successfully

cat > /etc/network/interfaces <<EOF
auto lo
iface lo inet loopback
EOF

ifup lo

# Fallback to cgroup v1 by unmounting cgroup v2 since the Rescue OS Alpine Linux build has v2 enabled by default.
# Without unmounting cgroup v2, qemu will throw an error when starting a VM.

umount /sys/fs/cgroup

# Install KVM hypervisor
# VM xml config files are stored in /etc/libvirt/qemu  e.g. xepa.xml
# All configuration files are located in directory /etc/libvirt
# Each VM will have its own configuration file in directory /etc/libvirt/qemu, e.g. debian12.xml
# Each VM configuration file contains the path to its image file.
# Storage pools will be defined in directory /etc/libvirt/storage
# A VM image file will by default be created in directory /var/lib/libvirt/images, i.e. the storage pool normally defined by file /etc/libvirt/storage/default.xml
# Directory /var/lib/libvirt contains other subdirectories.
# You can define other storage pool locations when creating a VM in virt-manager.
# QEMU logs for each VM / Domain are stored in /var/log/libvirt/qemu  e.g. /var/log/libvirt/qemu/xepa.log which shows the /usr/bin/qemu-system-x86_64 command parameters.

apk add libvirt-daemon qemu-img qemu-system-x86_64 qemu-modules virt-manager virt-install \
--update

# Check Alpine Linux version with cat /etc/*release*  and  cat /etc/issue
# Check QEMU version with /usr/bin/qemu-system-x86_64 --version
# Check libvirt version with virsh version --daemon  or libvirtd --version

# NOTE: It looks like QEMU 8.2.0 from the edge branch isn't working with PCI VFIO passthrough.
# It throws this error when starting a VM:
# qemu unexpectedly closed the monitor
# Using QEMU 8.1.3 from the latest-stable branch fixes the issue.

# Replace OVMF UEFI firmware file included in stable QEMU 8.1.3 with newer version to fix the issue of Windows 11 not booting and getting stuck at TianoCore logo
# You can see all firmware files from the main branch on the link below or select a specific branch / tag release version
# https://gitlab.com/qemu-project/qemu/-/tree/master/pc-bios
rm /usr/share/qemu/edk2-x86_64-secure-code.fd
wget https://gitlab.com/qemu-project/qemu/-/raw/v8.2.0/pc-bios/edk2-x86_64-secure-code.fd.bz2 -P /usr/share/qemu
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

apk add swtpm libtpms --update

# Start libvirtd service

rc-service libvirtd start

# Sometimes the virtlogd service doesn't get started automatically which causes the error "failed to connect socket to '/var/run/libvirt/virtlogd-sock'" to happen when starting a VM so we're starting the service manually
rc-service virtlogd start

# Install web-browser (Firefox works, Chromium seems to throw an I/O error and doesn't launch)

apk add firefox-esr \
--update

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

# setting -a address to 0.0.0.0 lets filebrowser listen to all host IPs

nohup filebrowser -r /root -a 0.0.0.0 -p 8080 > /dev/null 2>&1 &

mkdir /root/Downloads

clear


ETH0_PUBLIC_IPV4=$(echo $METADATA | jq -r ".network.addresses[] | select(.public == true) | select(.address_family == 4) | .address")
ETH0_PUBLIC_IPV4_NETMASK=$(echo $METADATA | jq -r ".network.addresses[] | select(.public == true) | select(.address_family == 4) | .netmask")
ETH0_PUBLIC_IPV4_CIDR=$(echo $METADATA | jq -r ".network.addresses[] | select(.public == true) | select(.address_family == 4) | .cidr")
ETH0_PUBLIC_IPV4_GATEWAY=$(echo $METADATA | jq -r ".network.addresses[] | select(.public == true) | select(.address_family == 4) | .gateway")

INSTANCE_ID=$(echo $METADATA | jq -r .id)
METRO=$(echo $METADATA | jq -r .metro)
PLAN=$(echo $METADATA | jq -r .plan)
API_METADATA=$(curl -s -X GET -H "X-Auth-Token: $AUTH_TOKEN" "https://api.packet.net/devices/$INSTANCE_ID?include=project_lite")
PROJECT_UUID=$(echo $API_METADATA | jq -r .project_lite.id)


# This virsh command lists PCI devices and their tree
# virsh nodedev-list --tree

# Network Interface PCI information

# lshw -c network

NETWORK_PCI_LIST=""

#IFS=$'\n'
INTERFACES_COUNT=$(echo $METADATA | jq '.network.interfaces | length')

#if [ "$INTERFACES_COUNT" -gt  "2" ];then

   # get network port mac address for eth2 on 4 port servers
#   MANAGEMENT_METADATA_MAC=$(echo $METADATA | jq -r '.network.interfaces[] | select(.name == "eth2") | .mac')
#   ETH0_METADATA_MAC=$(echo $METADATA | jq -r '.network.interfaces[] | select(.name == "eth0") | .mac')

#else

   # get network port mac address for eth1 on 2 port servers
#   MANAGEMENT_METADATA_MAC=$(echo $METADATA | jq -r '.network.interfaces[] | select(.name == "eth1") | .mac')
#   ETH0_METADATA_MAC=$(echo $METADATA | jq -r '.network.interfaces[] | select(.name == "eth0") | .mac')

#fi

# get secondary bond0 network port mac address
# MANAGEMENT_METADATA_MAC=$(echo $API_METADATA | jq -r '.network_ports[] | select(.bond.name == "bond0")' | jq -r --slurp '.[1].data.mac')
MANAGEMENT_METADATA_MAC=$(echo $API_METADATA | jq -r '.network_ports[] | select(.bond.name == "bond0")' | jq -r --slurp 'last.data.mac')
ETH0_METADATA_MAC=$(echo $METADATA | jq -r '.network.interfaces[] | select(.name == "eth0") | .mac')

echo > /root/pci-device-info
echo "Network interfaces:" >> /root/pci-device-info
echo >> /root/pci-device-info

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

    # Get proper management interface by checking the metadata with the OS
    if [ "$MANAGEMENT_METADATA_MAC" == "$LOCAL_MAC" ]; then
        MANAGEMENT_IF_NAME=$LINE
    fi

    # Get proper eth0 interface by checking the metadata with the OS
    if [ "$ETH0_METADATA_MAC" == "$LOCAL_MAC" ]; then
        ETH0_IF_NAME=$LINE
    fi

    PCI_ID=$(grep PCI_SLOT_NAME /sys/class/net/$LINE/device/uevent | cut -d "=" -f2)


    # Add only the eth0 interface / NIC to the XEPA ISO VM

    if [ "$ETH0_METADATA_MAC" == "$LOCAL_MAC" ]; then
        ETH0_PCI_ID=$PCI_ID
        if [[ -z "$NETWORK_PCI_LIST" ]]; then
           # $NETWORK_PCI_LIST is empty, do what you want
           # echo "PCI list is empty"
           NETWORK_PCI_LIST=$NETWORK_PCI_LIST$PCI_ID
        else
           # echo "PCI list is not empty"
           NETWORK_PCI_LIST=$NETWORK_PCI_LIST$'\n'$PCI_ID
        fi
    fi


# This is code to add all network interfaces to the XEPA ISO VM

#PCI_EXISTS_IN_LIST="false"

# Only add network interfaces that aren't used for management

# if [ "$MANAGEMENT_METADATA_MAC" != "$LOCAL_MAC" ]; then

#for PCI in $NETWORK_PCI_LIST
#do
#    if [ "$PCI_ID" == "$PCI" ]; then
        # To add duplicate PCI IDs just comment out the next line # PCI_EXISTS_IN_LIST="true"
#        PCI_EXISTS_IN_LIST="true"
#    fi
#done

#if [ "$PCI_EXISTS_IN_LIST" == "false" ]; then

#    if [[ -z "$NETWORK_PCI_LIST" ]]; then
       # $NETWORK_PCI_LIST is empty, do what you want
       # echo "PCI list is empty"
#       NETWORK_PCI_LIST=$NETWORK_PCI_LIST$PCI_ID
#    else
       # echo "PCI list is not empty"
#       NETWORK_PCI_LIST=$NETWORK_PCI_LIST$'\n'$PCI_ID
#    fi

#fi

#fi


# only add API Interface name if OS name is different

    if [ "$METADATA_IF_NAME" == "$LINE" ]; then
        lspci -D | grep $PCI_ID | sed 's#^#PCI BDF #' | sed "s/$/ ($LINE)/" >> /root/pci-device-info
    else
        lspci -D | grep $PCI_ID | sed 's#^#PCI BDF #' | sed "s/$/ ($LINE)/" | sed "s/$/ (API name: $METADATA_IF_NAME)/" >> /root/pci-device-info
    fi

    echo >> /root/pci-device-info
    break
fi
done
done


# Storage drive information and PCI mapping

# lshw -c storage

STORAGE_PCI_LIST=""

IFS=$'\n' >> /root/pci-device-info
echo >> /root/pci-device-info
echo "Local storage drives:" >> /root/pci-device-info
echo >> /root/pci-device-info

#SATA drives
for LINE in $(ls -l /sys/block/ | grep "sd" | awk '{print $9, $10, $11}')
do

# Get the amount of words separated by a backslash
# Then run a a while loop starting from word count and reducing by one so we go in the left direction and stop when you find the first word that matches the format of a PCI address
# Some servers have their storage controllers connected to host or PCI bridges which have their own PCI addresses so that's why we need to start from the right end and go towards the left
WORD_COUNT=$(echo $LINE | grep -o "/" | wc -l)
WORD_COUNT=$(( WORD_COUNT + 1 ))
PCI_ID_FOUND=false
while [ $WORD_COUNT -gt 1 ] && [ $PCI_ID_FOUND == "false" ]; do
    if [ $(echo $LINE | cut -d "/" -f$WORD_COUNT | grep -Eo "....:..:..\..") ]; then
        PCI_ID_FOUND=true
        PCI_ID=$(echo $LINE | cut -d "/" -f$WORD_COUNT)
    else
        WORD_COUNT=$(( WORD_COUNT - 1 ))
    fi
done

PCI_EXISTS_IN_LIST="false"

for PCI in $STORAGE_PCI_LIST
do
    if [ "$PCI_ID" == "$PCI" ]; then
        # To add duplicate PCI IDs just comment out the next line # PCI_EXISTS_IN_LIST="true"
        PCI_EXISTS_IN_LIST="true"
    fi
done

if [ "$PCI_EXISTS_IN_LIST" == "false" ]; then

    if [[ -z "$STORAGE_PCI_LIST" ]]; then
       # $STORAGE_PCI_LIST is empty, do what you want
       # echo "PCI list is empty"
       STORAGE_PCI_LIST=$STORAGE_PCI_LIST$PCI_ID
    else
       # echo "PCI list is not empty"
       STORAGE_PCI_LIST=$STORAGE_PCI_LIST$'\n'$PCI_ID
    fi

fi


lspci -D | grep $PCI_ID | sed 's#^#PCI BDF #' >> /root/pci-device-info
DEVICE_PATH=$(echo $LINE | awk '{print $1}' | sed 's#^#/dev/#') >> /root/pci-device-info
lsblk -p -o NAME,TYPE,SIZE,MODEL,TRAN,ROTA,HCTL,MOUNTPOINT $DEVICE_PATH | sed 's#NAME#PATH#' | sed 's#ROTA#DRIVE-TYPE#' | sed 's# 0 #SSD      #' | sed 's# 1 #HDD      #' >> /root/pci-device-info
echo >> /root/pci-device-info

done


#NVMe drives
for LINE in $(ls -l /sys/block/ | grep "nvme" | awk '{print $9, $10, $11}')
do

# Get the amount of words separated by a backslash
# Then run a a while loop starting from word count and reducing by one so we go in the left direction and stop when you find the first word that matches the format of a PCI address
# Some servers have their storage controllers connected to host or PCI bridges which have their own PCI addresses so that's why we need to start from the right end and go towards the left
WORD_COUNT=$(echo $LINE | grep -o "/" | wc -l)
WORD_COUNT=$(( WORD_COUNT + 1 ))
PCI_ID_FOUND=false
while [ $WORD_COUNT -gt 1 ] && [ $PCI_ID_FOUND == "false" ]; do
    if [ $(echo $LINE | cut -d "/" -f$WORD_COUNT | grep -Eo "....:..:..\..") ]; then
        PCI_ID_FOUND=true
        PCI_ID=$(echo $LINE | cut -d "/" -f$WORD_COUNT)
    else
        WORD_COUNT=$(( WORD_COUNT - 1 ))
    fi
done

# Only add NVMe PCI devices if the server is in UEFI boot mode as NVMe can only be used as bootable drives in UEFI mode. Legacy BIOS does not support NVMe devices as bootable drives.
if [ -d /sys/firmware/efi ]; then

PCI_EXISTS_IN_LIST="false"

for PCI in $STORAGE_PCI_LIST
do
    if [ "$PCI_ID" == "$PCI" ]; then
        # To add duplicate PCI IDs just comment out the next line # PCI_EXISTS_IN_LIST="true"
        PCI_EXISTS_IN_LIST="true"
    fi
done

if [ "$PCI_EXISTS_IN_LIST" == "false" ]; then

    if [[ -z "$STORAGE_PCI_LIST" ]]; then
       # $STORAGE_PCI_LIST is empty, do what you want
       # echo "PCI list is empty"
       STORAGE_PCI_LIST=$STORAGE_PCI_LIST$PCI_ID
    else
       # echo "PCI list is not empty"
       STORAGE_PCI_LIST=$STORAGE_PCI_LIST$'\n'$PCI_ID
    fi

fi

fi

lspci -D | grep $PCI_ID | sed 's#^#PCI BDF #' >> /root/pci-device-info
DEVICE_PATH=$(echo $LINE | awk '{print $1}' | sed 's#^#/dev/#') >> /root/pci-device-info
lsblk -p -o NAME,TYPE,SIZE,MODEL,TRAN,ROTA,HCTL,MOUNTPOINT $DEVICE_PATH | sed 's#NAME#PATH#' | sed 's#ROTA#DRIVE-TYPE#' | sed 's# 0 #SSD      #' | sed 's# 1 #HDD      #' >> /root/pci-device-info
echo >> /root/pci-device-info

done

cat /root/pci-device-info

# virt-install PCI device boot order

VIRT_INSTALL_PCI_DEVICES=''

NUM=0
for LINE in $STORAGE_PCI_LIST
do
  echo $LINE
  NUM=$(( NUM + 1 ))
  echo $NUM
  IFS=$'\n'
  echo
  
  PCI_DOMAIN=$(echo $LINE | cut -d ":" -f1)
  PCI_BUS=$(echo $LINE | cut -d ":" -f2)
  PCI_SLOT=$(echo $LINE | cut -d ":" -f3 | cut -d "." -f1)
  PCI_FUNCTION=$(echo $LINE | cut -d ":" -f3 | cut -d "." -f2)

  # Count how many functions are available for a specific pci device
  PCI_DEV_ADDRESS=$(echo $LINE | cut -d "." -f1)
  PCI_DEV_FUNCTION_COUNT=$(lspci -D -s $PCI_DEV_ADDRESS.* | wc -l)

  if [ "$PCI_DEV_FUNCTION_COUNT" -gt "1" ]; then
      # echo "PCI device is multifunction capable"
      PCI_MULTI_FUNCTION=on
  else
      PCI_MULTI_FUNCTION=off
  fi

  VIRT_INSTALL_PCI_DEVICES=$VIRT_INSTALL_PCI_DEVICES$'--host-device='$LINE$',boot.order='$NUM,address.type=pci,address.multifunction=$PCI_MULTI_FUNCTION,address.domain=0x$PCI_DOMAIN,address.bus=0x$PCI_BUS,address.slot=0x$PCI_SLOT,address.function=0x$PCI_FUNCTION$' '
  
done

NUM=$(( NUM + 1 ))
#CDROM boot order ^
VIRT_INSTALL_PCI_DEVICES=$VIRT_INSTALL_PCI_DEVICES$'--disk device=cdrom,bus=sata,boot.order='$NUM$' '


for LINE in $NETWORK_PCI_LIST
do
  echo $LINE
  NUM=$(( NUM + 1 ))
  echo $NUM
  IFS=$'\n'
  echo

  PCI_DOMAIN=$(echo $LINE | cut -d ":" -f1)
  PCI_BUS=$(echo $LINE | cut -d ":" -f2)
  PCI_SLOT=$(echo $LINE | cut -d ":" -f3 | cut -d "." -f1)
  PCI_FUNCTION=$(echo $LINE | cut -d ":" -f3 | cut -d "." -f2)

  # Count how many functions are available for a specific pci device
  PCI_DEV_ADDRESS=$(echo $LINE | cut -d "." -f1)
  PCI_DEV_FUNCTION_COUNT=$(lspci -D -s $PCI_DEV_ADDRESS.* | wc -l)

  if [ "$PCI_DEV_FUNCTION_COUNT" -gt "1" ]; then
      # echo "PCI device is multifunction capable"
      PCI_MULTI_FUNCTION=on
  else
      PCI_MULTI_FUNCTION=off
  fi


  # Bit 7 of the Header Type register (Offset 0E (hexadecimal) which means byte 14 (decimal) starting from byte 0) in the PCI configuration space is used to determine if the device has multiple functions.
  # There are 8 bits in a byte and it starts from bit 0 to 7 so bit 7 is the last one.
  # If bit 7 of the register is set (binary value 1), the device has multiple functions, otherwise (binary value 0) it is a single function device.
  # Check offset 0E in byte form for a specific PCI device BDF address:
  # setpci -s 0000:8a:00.0 0E.B
  # Alternatively lspci will display the standard hex-dump of the standard part of the config space, out of which we need only the first line (256 bytes) i.e PCI Device Structure.
  # lspci -x -s 0000:8a:00.0
  # 00: is the offset or starting byte of the line. The next line would be 10: which means byte 16 and so on.
  #     00 <-- byte 0                  byte 14 --> 0E
  # 00: 72 11 00 00 06 01 10 00 01 00 00 ff 08 00 |80| 00
  #
  # If byte 14 (offset 0E) is set (value = 0x80 or something else, setpci returns just 80), the device is multi-function -- else it is not.
  # You can convert the hex value 80 or whatever value you get to binary which should be 10000000
  #                                                                 Bits 01234567
  # You then need to reverse the order of the binary value so it becomes 00000001
  # So in this case Bit 7 is set to 1 so the PCI devices is multifunction capable.
  # The reason for reversing the binary value might have to do with endianness or because the PCI config space is in reverse. Most general purpose computers use little-endian.

#  You can use this command to get offset 0E in binary form. Replace 0000:8a:00.0 with your PCI device address.
#  echo "obase=2; ibase=16; $(lspci -x -s 0000:8a:00.0 | grep "00: \|\." | cut -d ' ' -f16)" | bc | rev
#  Show Bit 7:  (8th bit if you count from 1)
#  echo "obase=2; ibase=16; $(lspci -x -s 0000:8a:00.0 | grep "00: \|\." | cut -d ' ' -f16)" | bc | rev | cut -c 8
#  Alternative option for binary form:
#  echo "obase=2; ibase=16; $(setpci -s 0000:8a:00.0 0E.B)" | bc | rev
#  Show Bit 7:  (8th bit if you count from 1)
#  echo "obase=2; ibase=16; $(setpci -s 0000:8a:00.0 0E.B)" | bc | rev | cut -c 8

#  Script to show all pci devices and their offset 0E in binary
#  Needs to run with bash (apk add bash): /bin/bash

#  lspci -x | grep "00: \|\." | while read -r line ; do
#  if [[ "$line" == *"."* ]]; then
#    echo $line
#  else
#    header_type=`echo $line | cut -d ' ' -f16`
#    bin=`echo "obase=2; ibase=16; $header_type" | bc | rev`
#    printf "%08d\n" $bin
#  fi
#  done

  
  # There's no need to add network devices to the boot order unless you need it for troubleshooting
  #  VIRT_INSTALL_PCI_DEVICES=$VIRT_INSTALL_PCI_DEVICES--host-device=$LINE$',boot.order='$NUM$' '
  VIRT_INSTALL_PCI_DEVICES=$VIRT_INSTALL_PCI_DEVICES$'--host-device='$LINE,address.type=pci,address.multifunction=$PCI_MULTI_FUNCTION,address.domain=0x$PCI_DOMAIN,address.bus=0x$PCI_BUS,address.slot=0x$PCI_SLOT,address.function=0x$PCI_FUNCTION$' '


  # This qemu command shows a list of available devices that can be emulated
  # /usr/bin/qemu-system-x86_64 -device ?
  # Create virtual network adapter using the same MAC Address and PCI address as eth0
  # The virtual network adapter is used as a fallback for servers that don't support IOMMU / PCI Passthrough
  
  ETH0_PCI_DOMAIN=$(echo $ETH0_PCI_ID | cut -d ":" -f1)
  ETH0_PCI_BUS=$(echo $ETH0_PCI_ID | cut -d ":" -f2)
  ETH0_PCI_SLOT=$(echo $ETH0_PCI_ID | cut -d ":" -f3 | cut -d "." -f1)
  ETH0_PCI_FUNCTION=$(echo $ETH0_PCI_ID | cut -d ":" -f3 | cut -d "." -f2)

  # Count how many functions are available for a specific pci device
  ETH0_PCI_DEV_ADDRESS=$(echo $ETH0_PCI_ID | cut -d "." -f1)
  ETH0_PCI_DEV_FUNCTION_COUNT=$(lspci -D -s $ETH0_PCI_DEV_ADDRESS.* | wc -l)

  if [ "$ETH0_PCI_DEV_FUNCTION_COUNT" -gt "1" ]; then
      # echo "PCI device is multifunction capable"
      ETH0_PCI_MULTI_FUNCTION=on
  else
      ETH0_PCI_MULTI_FUNCTION=off
  fi
  
  VIRT_INSTALL_VIRTUAL_NETWORK_ADAPTER=$'--network 'network=default,model.type=e1000e,mac.address=$ETH0_METADATA_MAC,address.type=pci,address.multifunction=$ETH0_PCI_MULTI_FUNCTION,address.domain=0x$ETH0_PCI_DOMAIN,address.bus=0x$ETH0_PCI_BUS,address.slot=0x$ETH0_PCI_SLOT,address.function=0x$ETH0_PCI_FUNCTION$' '
  
done

echo "$VIRT_INSTALL_PCI_DEVICES"

# $VIRT_INSTALL_PCI_DEVICES contains the host PCI devices that will be passed to the XEPA VM.
# virt-install / libvirt have the ability to define the PCI address that the device will appear as in the guest VM and we're setting it to match with the host PCI device address.
# The only difference between the host and guest will be the PCI bus id / pcie-root-port / physical slot and it seems to be difficult or impossible to make the VM match with the host.
# Some operating systems such as Ubuntu will assign different network interface names for PCI NICs while attached to the VM versus the host due to that slot number / physical location difference.
# However this is not an issue as the network interface configuration will still persist due to the matching PCI address of the host and guest vm. Ubuntu will show the guest vm's interface name as altname when you run ip a.
# You can check the Physical Slot with  lspci -v -D -s 0000:8a:00.0
# The pci physical slot and address assocation is found with: cat /sys/bus/pci/slots/${slot_num}/address
# For newer linux distributions you might see network interface names like the following:
# eno: Names containing the index numbers provided by firmware/BIOS for on-board devices, example: eno1 (eno = Onboard).
# ens: Names containing the PCI Express hotplug slot numbers provided by the firmware/BIOS, example: ens1 (ens = Slot).
# enp: Names containing the physical/geographical location of the hardware's port, example 1: enp2s0 (enp = Position)  example 2: enp2s0f0np0 (enp2 = position, s0 = pci slot 0, f0 = function 0 and it only appears if the device is multifunction capable, np0 = network port number 0 and it could also be network port name as well which seems to be defined by the NIC driver) 
# enx: Names containing the MAC address of the interface (example: enx78e7d1ea46da).
# eth: Classic unpredictable kernel-native ethX naming (example: eth0).


# Passing a string of parameters as a variable to virt-install doesn't seem to work as it seems like a formatting issue
# It works by evaluating the content of the string as shell code
# eval "$VIRT_INSTALL_PARAMS$VIRT_INSTALL_PCI_DEVICES"

VIRT_INSTALL_PARAMS='virt-install --name xepa --description "XEPA ISO Installer VM" --os-variant=generic --arch x86_64 --machine q35 --sysinfo host --cpu host-passthrough --vcpus=8 --ram=30000 --import --serial pty,target.port=0 --serial pty,target.port=1 --tpm model=tpm-crb,type=emulator,version=2.0 --noreboot --noautoconsole '

# Useful virt-install options
# --os-variant detect=off \
# --os-variant detect=on \
# --virt-type kvm \
# --machine q35  using q35 chipset instead of i440fx is required for PCIe support otherwise passing specific PCI IDs to the guest instead of getting random IDs like address.domain=0x$PCI_DOMAIN will not work

# -d check in shell returns true if directory exists

if [ -d /sys/firmware/efi ]; then
    VIRT_INSTALL_PARAMS=$VIRT_INSTALL_PARAMS$'--boot uefi '

    # Secure Boot is a UEFI/EFI feature, and requires a UEFI/EFI-based firmware to function. Legacy BIOS does not support Secure Boot.
    
    SECURE_BOOT_STATE=$(mokutil --sb-state | grep "SecureBoot")
    # Returns  SecureBoot enabled  or  SecureBoot disabled

    if [ "$SECURE_BOOT_STATE" == "SecureBoot enabled" ]; then
    #    VIRT_INSTALL_PARAMS=$VIRT_INSTALL_PARAMS$'--boot loader=/usr/share/qemu/edk2-x86_64-secure-code.fd,loader.readonly=yes,loader.type=pflash '
    #    VIRT_INSTALL_PARAMS=$VIRT_INSTALL_PARAMS$'--boot uefi,loader.secure=no '
        VIRT_INSTALL_PARAMS=$VIRT_INSTALL_PARAMS$'--boot loader.secure=yes '
    elif [ "$SECURE_BOOT_STATE" == "SecureBoot disabled" ]; then
        VIRT_INSTALL_PARAMS=$VIRT_INSTALL_PARAMS$'--boot loader.secure=no '
    fi
    
fi


# This one is not reliable for checking IOMMU state
# find /sys | grep dmar

# shell string checks
# -n  string is not null.
# -z  string is null, that is, has zero length

# ls -l /sys/class/iommu/*/devices

if [ -n "$(ls /sys/class/iommu)" ];
then
#  echo "contains files, iommu enabled in bios/uefi"
  IOMMU_STATE="enabled"
else
#  echo "empty, iommu disabled in bios/uefi"
  IOMMU_STATE="disabled"
fi

printf "\n"

# The c3.small.x86 has IOMMU enabled but it doesn't properly support PCI passthrough so we're falling back to the disabled state
if [ "$PLAN" == "c3.small.x86" ]; then
    IOMMU_STATE="disabled"
fi

if [ "$IOMMU_STATE" == "enabled" ]; then
    VIRT_INSTALL_PARAMS=$VIRT_INSTALL_PARAMS$'--nonetworks '
    echo "$VIRT_INSTALL_PARAMS$VIRT_INSTALL_PCI_DEVICES"
    eval "$VIRT_INSTALL_PARAMS$VIRT_INSTALL_PCI_DEVICES"
fi

if [ "$IOMMU_STATE" == "disabled" ]; then

    NUM=0

    # Fallback to creating virtual disks when IOMMU / PCI Passthrough is disabled by using qemu block device passthrough

    for LINE in $(ls -l /sys/block/ | grep "sd" | awk '{print $9}')
    do
        NUM=$(( NUM + 1 ))
        VIRT_INSTALL_VIRTUAL_STORAGE_DISKS_PASSTHROUGH=$VIRT_INSTALL_VIRTUAL_STORAGE_DISKS_PASSTHROUGH$'--disk '/dev/$LINE,boot.order=$NUM$' '
        
    done

    # Only add NVMe devices if the server is in UEFI boot mode as NVMe can only be used as bootable drives in UEFI mode. Legacy BIOS does not support NVMe devices as bootable drives.
    if [ -d /sys/firmware/efi ]; then
        for LINE in $(ls -l /sys/block/ | grep "nvme" | awk '{print $9}')
        do
            NUM=$(( NUM + 1 ))
            VIRT_INSTALL_VIRTUAL_STORAGE_DISKS_PASSTHROUGH=$VIRT_INSTALL_VIRTUAL_STORAGE_DISKS_PASSTHROUGH$'--disk '/dev/$LINE,boot.order=$NUM$' '
        done
    fi

    NUM=$(( NUM + 1 ))
    
    # Don't add PCI devices as it's not supported when IOMMU / PCI Passthrough is disabled
    # Use virtual network adapter and storage disks instead
    echo "$VIRT_INSTALL_PARAMS$VIRT_INSTALL_VIRTUAL_NETWORK_ADAPTER$VIRT_INSTALL_VIRTUAL_STORAGE_DISKS_PASSTHROUGH--disk device=cdrom,bus=sata,boot.order=$NUM"
    eval "$VIRT_INSTALL_PARAMS$VIRT_INSTALL_VIRTUAL_NETWORK_ADAPTER$VIRT_INSTALL_VIRTUAL_STORAGE_DISKS_PASSTHROUGH--disk device=cdrom,bus=sata,boot.order=$NUM"
fi



echo "INSTANCE ID: $INSTANCE_ID"
echo "METRO: $METRO"
echo "PROJECT ID: $PROJECT_UUID"

        echo "Creating the XEPA-MANAGEMENT VLAN..."
        sleep 1
        VXLAN=1337
        VLAN_CREATED=false

        # Check if VLAN has been created already and use it
        VLAN_CHECK_IF_EXISTS=$(curl -s -X GET -H "X-Auth-Token: $AUTH_TOKEN" "https://api.packet.net/projects/$PROJECT_UUID/virtual-networks?per_page=250&metro=$METRO" | jq -r '.virtual_networks[] | select(.description == "xepa-management-'$INSTANCE_ID'")')
        if [ -n "$VLAN_CHECK_IF_EXISTS" ]; then
            if (echo $VLAN_CHECK_IF_EXISTS | jq -e 'has("errors")' > /dev/null); then
                echo $VLAN_CHECK_IF_EXISTS | jq
                echo "checking for existing vlan failed, trying to create a new vlan..."
            else
                # VLAN ALREADY EXISTS
                echo "VLAN already exists"
                echo $VLAN_CHECK_IF_EXISTS | jq
                VLAN_UUID=$(echo $VLAN_CHECK_IF_EXISTS | jq -r .id)
                VLAN_CREATED=true
            fi
        fi
        
        while [ "$VLAN_CREATED" = "false" ]; do
        OUTPUT=$(curl -s "https://api.equinix.com/metal/v1/projects/$PROJECT_UUID/virtual-networks" \
                -X POST \
                -H "Content-Type: application/json" \
                -H "X-Auth-Token: $AUTH_TOKEN" \
                --data '{
                        "vxlan":'$VXLAN',
                        "metro":"'${METRO}'",
                        "description":"xepa-management-'$INSTANCE_ID'"
                }')
        sleep 1
        if (echo $OUTPUT | jq -e 'has("errors")' > /dev/null); then
                echo $OUTPUT | jq
                if [ $(echo $OUTPUT | jq .errors | grep -Eo "already has a vlan") ]; then
                    echo "VLAN $VXLAN already exists, trying another VLAN ID"
                    VXLAN=$(( VXLAN + 1 ))
                else
                    echo "VLAN is required to proceed, try again, exiting..."
                    exit
                fi
        else
                echo "Here is the new VLAN..."
                echo "$OUTPUT" | jq
                VLAN_UUID=$(echo $OUTPUT | jq -r .id)
                VLAN_CREATED=true
                echo "Done..."
        fi
        done

        echo "Creating the Elastic IP Block..."
        sleep 1

        ELASTIC_IP_BLOCK_CREATED=false

        # Check if Elastic IP block has been created already and use it
        ELASTIC_IP_CHECK_IF_EXISTS=$(curl -s -X GET -H "X-Auth-Token: $AUTH_TOKEN" "https://api.packet.net/projects/$PROJECT_UUID/ips?per_page=250&metro=$METRO&public=true&ipv4=true" | jq -r '.ip_addresses[] | select(.details == "xepa-management-'$INSTANCE_ID'")')
        if [ -n "$ELASTIC_IP_CHECK_IF_EXISTS" ]; then
            if (echo $ELASTIC_IP_CHECK_IF_EXISTS | jq -e 'has("errors")' > /dev/null); then
                echo $ELASTIC_IP_CHECK_IF_EXISTS | jq
                echo "checking for existing Elastic IP failed, trying to create a new IP block..."
            else
                # ELASTIC IP BLOCK ALREADY EXISTS
                echo "Elastic IP block already exists"
                echo $ELASTIC_IP_CHECK_IF_EXISTS | jq
                IP_UUID=$(echo $ELASTIC_IP_CHECK_IF_EXISTS | jq -r .id)
                SERVER_IP=$(echo $ELASTIC_IP_CHECK_IF_EXISTS | jq -r .address)
                NETMASK=$(echo $ELASTIC_IP_CHECK_IF_EXISTS | jq -r .netmask)
                CIDR=$(echo $ELASTIC_IP_CHECK_IF_EXISTS | jq -r .cidr)
                GATEWAY=$(echo $ELASTIC_IP_CHECK_IF_EXISTS | jq -r .gateway)
                ELASTIC_IP_BLOCK_CREATED=true
                echo "Done..."
            fi
        fi
        

        if [ "$ELASTIC_IP_BLOCK_CREATED" == "false" ]; then
        
        OUTPUT=$(curl -s "https://api.equinix.com/metal/v1/projects/$PROJECT_UUID/ips" \
                -X POST \
                -H "Content-Type: application/json" \
                -H "X-Auth-Token: $AUTH_TOKEN" \
                --data '{
                        "quantity":8,
                        "metro":"'$METRO'",
                        "type":"public_ipv4",
                        "comments":"",
                        "customdata":"",
                        "details":"xepa-management-'$INSTANCE_ID'",
                        "tags":[]
                }')
        sleep 1
        if (echo $OUTPUT | jq -e 'has("errors")' > /dev/null); then
                echo $OUTPUT | jq
                echo "Elastic IP block is required to proceed, try again, exiting..."
                exit
        else
                echo "Here is the new Elastic IP Block..."
                echo "$OUTPUT" | jq
                IP_UUID=$(echo $OUTPUT | jq -r .id)
                SERVER_IP=$(echo $OUTPUT | jq -r .address)
                NETMASK=$(echo $OUTPUT | jq -r .netmask)
                GATEWAY=$(echo $OUTPUT | jq -r .gateway)
                ELASTIC_IP_BLOCK_CREATED=true
                echo "Done..."
        fi

        fi

        METAL_GATEWAY_CREATED=false

        # Check if Metal Gateway has been created already and use it
        METAL_GATEWAY_CHECK_IF_EXISTS=$(curl -s -X GET -H "X-Auth-Token: $AUTH_TOKEN" "https://api.packet.net/projects/$PROJECT_UUID/metal-gateways?per_page=250&include=virtual_network,ip_reservation" | jq -r '.metal_gateways[] | select(.ip_reservation.id == "'$IP_UUID'")')
        if [ -n "$METAL_GATEWAY_CHECK_IF_EXISTS" ]; then
            if (echo $METAL_GATEWAY_CHECK_IF_EXISTS | jq -e 'has("errors")' > /dev/null); then
                echo $METAL_GATEWAY_CHECK_IF_EXISTS | jq
                echo "checking for existing Elastic IP failed, trying to create a new IP block..."
            else
                # METAL GATEWAY ALREADY EXISTS
                echo "Metal Gateway already exists"
                #echo $METAL_GATEWAY_CHECK_IF_EXISTS | jq
                echo "$METAL_GATEWAY_CHECK_IF_EXISTS" | jq -r '{ "Metal Gateway ID":.id, "Metro":.virtual_network.metro_code, "VLAN":.virtual_network.vxlan, "Subnet":.ip_reservation | "\(.network)/\(.cidr)", "Gateway IP":.ip_reservation.gateway}'
                METAL_GATEWAY_CREATED=true
                echo "Done..."
            fi
        fi
        

        if [ "$METAL_GATEWAY_CREATED" == "false" ]; then

        echo "Creating the Metal Gateway..."
        sleep 1
        OUTPUT=$(curl -s "https://api.equinix.com/metal/v1/projects/$PROJECT_UUID/metal-gateways?include=virtual_network,ip_reservation" \
                -X POST \
                -H "Content-Type: application/json" \
                -H "X-Auth-Token: $AUTH_TOKEN" \
                --data '{
                        "virtual_network_id":"'"$VLAN_UUID"'",
                        "ip_reservation_id":"'"$IP_UUID"'"
                }')
        sleep 1
        if (echo $OUTPUT | jq -e 'has("errors")' > /dev/null); then
                echo $OUTPUT | jq
                echo "Metal Gateway is required to proceed, try again, exiting..."
                exit
        else
                echo "Here is the new Metal Gateway..."
                echo "$OUTPUT" | jq -r '{ "Metal Gateway ID":.id, "Metro":.virtual_network.metro_code, "VLAN":.virtual_network.vxlan, "Subnet":.ip_reservation | "\(.network)/\(.cidr)", "Gateway IP":.ip_reservation.gateway}'
                echo "Done..."
        fi

        fi

        # NETWORK_PORT_ID=$(echo $API_METADATA | jq -r '.network_ports[] | select(.bond.name == "bond0")' | jq -r --slurp '.[1].id')
        NETWORK_PORT_ID=$(echo $API_METADATA | jq -r '.network_ports[] | select(.bond.name == "bond0")' | jq -r --slurp 'last.id')

#if [ "$INTERFACES_COUNT" -gt  "3" ];then

   # get network port id for eth2 on 4 port servers
#   NETWORK_PORT_ID=$(echo $API_METADATA | jq -r '.network_ports[] | select(.name == "eth2") | .id')

#else

   # get network port id for eth1 on 2 port servers
#   NETWORK_PORT_ID=$(echo $API_METADATA | jq -r '.network_ports[] | select(.name == "eth1") | .id')

#fi

        echo "Converting the Server to Hybrid Un-Bonded networking mode..."
        sleep 1
        OUTPUT=$(curl -s "https://api.equinix.com/metal/v1/ports/$NETWORK_PORT_ID/disbond" \
                -X POST \
                -H "Content-Type: application/json" \
                -H "X-Auth-Token: $AUTH_TOKEN" \
                --data '')
        sleep 1
        if (echo $OUTPUT | jq -e 'has("errors")' > /dev/null); then
                echo $OUTPUT | jq
                echo 
        else
                echo "Done..."
        fi

        echo "Attaching XEPA-MANAGEMENT VLAN to the server..."
        sleep 1
        OUTPUT=$(curl -s "https://api.equinix.com/metal/v1/ports/$NETWORK_PORT_ID/vlan-assignments/batches" \
                -X POST \
                -H "Content-Type: application/json" \
                -H "X-Auth-Token: $AUTH_TOKEN" \
                --data '{
                        "vlan_assignments":[{"vlan":"'$VLAN_UUID'","state":"assigned","native":false}]
                }')
        sleep 1
        if (echo $OUTPUT | jq -e 'has("errors")' > /dev/null); then
                echo $OUTPUT | jq
        else
                echo "Done..."
        fi

cat >> /etc/network/interfaces <<EOF

auto $ETH0_IF_NAME
iface $ETH0_IF_NAME inet static
    address $ETH0_PUBLIC_IPV4
    netmask $ETH0_PUBLIC_IPV4_NETMASK

auto $MANAGEMENT_IF_NAME
iface $MANAGEMENT_IF_NAME inet static
    address $SERVER_IP
    netmask $NETMASK
EOF

ifup $MANAGEMENT_IF_NAME

ip route del default
ip route add default via $GATEWAY

# this is needed to make ifup sync with the current interface state otherwise ifdown won't work
ifup $ETH0_IF_NAME

# ifdown eth0 doesn't work when eth0 isn't defined in /etc/network/interfaces
ifdown $ETH0_IF_NAME

#ip link set $ETH0_IF_NAME down


cat > /root/cleanup.sh <<EOF
#!/bin/sh

# Since we are using the same variable names as the parent script we need to escape the $ and backslash character with a backslash \\

AUTH_TOKEN=$AUTH_TOKEN
INSTANCE_ID=$INSTANCE_ID
MANAGEMENT_IF_NAME=$MANAGEMENT_IF_NAME
ETH0_IF_NAME=$ETH0_IF_NAME
ETH0_PUBLIC_IPV4=$ETH0_PUBLIC_IPV4
ETH0_PUBLIC_IPV4_GATEWAY=$ETH0_PUBLIC_IPV4_GATEWAY
VLAN_UUID=$VLAN_UUID
IP_UUID=$IP_UUID
NETWORK_PORT_ID=$NETWORK_PORT_ID

if (virsh list --all | grep xepa > /dev/null); then

XEPA_VM_STATE=\$(virsh domstate xepa)

# if [ "\$XEPA_VM_STATE" == "running" ]; then

if [ "\$XEPA_VM_STATE" != "shut off" ]; then
    # Graceful shutdown command for xepa VM
    virsh shutdown xepa

    # Wait up to 60 seconds for the xepa VM to gracefully shut down
    echo "Waiting up to 60 seconds for the xepa VM to shut down gracefully"
    XEPA_VM_STATE=\$(virsh domstate xepa)
    SECONDS=1
    while [ "\$XEPA_VM_STATE" != "shut off" ] && [ \$SECONDS -lt 61 ]; do
        sleep 5
        XEPA_VM_STATE=\$(virsh domstate xepa)
        echo "XEPA VM State: \$XEPA_VM_STATE"
        SECONDS=\$(( SECONDS + 5 ))
    done
fi

if [ "\$XEPA_VM_STATE" != "shut off" ]; then
    # echo "true still running"
    # forcefully stop the xepa VM if it's not gracefully shutting down
    echo "XEPA VM seems stuck... forcefully shutting it down..."
    virsh destroy xepa
fi

virsh undefine xepa --nvram

fi

SECONDS=1
while [ -z "\$(ls -d /sys/class/net/*/ | cut -d '/' -f5 | grep "\$ETH0_IF_NAME")" ] && [ \$SECONDS -lt 21 ]; do
    echo "waiting for the primary management interface \$ETH0_IF_NAME to be available on the host..."
    sleep 5
    SECONDS=\$(( SECONDS + 5 ))
done

echo

if [ -z "\$(ls -d /sys/class/net/*/ | cut -d '/' -f5 | grep "\$ETH0_IF_NAME")" ]; then
    echo "the primary management interface \$ETH0_IF_NAME isn't available and it is required to proceed with the cleanup process"
    echo "exiting script..."
    exit
fi

echo "waiting for the primary management interface \$ETH0_IF_NAME to be available on the host..."
# sleep 15
echo

ifdown \$ETH0_IF_NAME
ifup \$ETH0_IF_NAME
ip route del default
ip route add default via \$ETH0_PUBLIC_IPV4_GATEWAY
ifdown \$MANAGEMENT_IF_NAME

sleep 5

# Check for internet connectivity
wget -q --spider http://google.com

if [ \$? -ne 0 ]; then
    echo
    echo "Server has no internet connectivity, exiting script... try again."
    echo "This could be due to the management eth0 interface still being attached to a virtual machine."
    echo
    exit
fi

# novnc needs to be reloaded as it seems like the network changes break it
while pkill -f "bash /root/noVNC/utils/novnc_proxy --vnc localhost:5900 --listen 80"; do
    sleep 1
done
nohup /root/noVNC/utils/novnc_proxy --vnc localhost:5900 --listen 80 > /dev/null 2>&1 &

        echo "Detaching XEPA-MANAGEMENT VLAN from the server..."
        sleep 1
        OUTPUT=\$(curl -s "https://api.equinix.com/metal/v1/ports/\$NETWORK_PORT_ID/vlan-assignments/batches" \\
                -X POST \\
                -H "Content-Type: application/json" \\
                -H "X-Auth-Token: \$AUTH_TOKEN" \\
                --data '{
                        "vlan_assignments":[{"vlan":"'\$VLAN_UUID'","state":"unassigned","native":false}]
                }')
        sleep 1
        if (echo \$OUTPUT | jq -e 'has("errors")' > /dev/null); then
                echo \$OUTPUT | jq
        else
                echo "Done..."
        fi

        # Deleting the Elastic IP block or VLAN associated with a Metal Gateway will automatically delete the Metal Gateway as well
        
        echo "Deleting Elastic IP block..."
        sleep 1
        OUTPUT=\$(curl -s "https://api.equinix.com/metal/v1/ips/\$IP_UUID" \\
                -X DELETE \\
                -H "Content-Type: application/json" \\
                -H "X-Auth-Token: \$AUTH_TOKEN" \\
                --data '')
        sleep 1
        if (echo \$OUTPUT | jq -e 'has("errors")' > /dev/null); then
                echo \$OUTPUT | jq
        else
                echo "Done..."
        fi

        # Giving the API some time to learn that there are no server network ports attached to the VLAN
        sleep 3

        echo "Deleting XEPA-MANAGEMENT VLAN..."
        sleep 1
        VLAN_DELETED=false
        ATTEMPT=1
        while [ "\$VLAN_DELETED" = "false" ] && [ "\$ATTEMPT" -lt 6 ]; do
        OUTPUT=\$(curl -s "https://api.equinix.com/metal/v1/virtual-networks/\$VLAN_UUID" \\
                -X DELETE \\
                -H "Content-Type: application/json" \\
                -H "X-Auth-Token: \$AUTH_TOKEN" \\
                --data '')
        sleep 1
        if (echo \$OUTPUT | jq -e 'has("errors")' > /dev/null); then
                echo \$OUTPUT | jq
                if (echo \$OUTPUT | jq .errors | grep -Eo "Cannot delete Virtual Network when port is assigned" > /dev/null); then
                    if [ "\$ATTEMPT" -eq 5 ]; then
                        echo "5 attempts to delete the VLAN failed, try again later, skipping this step..."
                        break
                    fi
                    echo "VLAN still has a server port attached"
                    echo "This is usually due to a minor delay until the API is aware that the port was detached from the VLAN"
                    echo "Trying to delete the XEPA-MANAGEMENT VLAN again..."
                    sleep 2
                    ATTEMPT=\$(( ATTEMPT + 1 ))
                else
                    break
                fi
        else
                VLAN_DELETED=true
                echo "Done..."
        fi
        done

        echo "Converting the Server to Layer 3 Bonded networking mode..."
        sleep 1
        SERVER_CONVERTED_TO_ORIGINAL_NETWORK_MODE=false
        ATTEMPT=1
        while [ "\$SERVER_CONVERTED_TO_ORIGINAL_NETWORK_MODE" = "false" ] && [ "\$ATTEMPT" -lt 6 ]; do
        OUTPUT=\$(curl -s "https://api.equinix.com/metal/v1/ports/\$NETWORK_PORT_ID/bond" \\
                -X POST \\
                -H "Content-Type: application/json" \\
                -H "X-Auth-Token: \$AUTH_TOKEN" \\
                --data '')
        sleep 1
        if (echo \$OUTPUT | jq -e 'has("errors")' > /dev/null); then
                echo \$OUTPUT | jq
                if (echo \$OUTPUT | jq .errors | grep -Eo "can't bond where virtual networks still assigned" > /dev/null); then
                    if [ "\$ATTEMPT" -eq 5 ]; then
                        echo "5 attempts to convert the network mode failed, check if you have other VLANs attached to the server, try again later, skipping this step..."
                        break
                    fi
                    echo "server port still has VLANs attached"
                    echo "This is usually due to a minor delay until the API is aware that the port was detached from the VLAN"
                    echo "Trying to convert the server network mode again..."
                    sleep 2
                    ATTEMPT=\$(( ATTEMPT + 1 ))
                else
                    break
                fi
        else
                SERVER_CONVERTED_TO_ORIGINAL_NETWORK_MODE=true
                echo "Done..."
        fi
        done
        

printf "\n"
echo "The ISO installation environment endpoint has changed to the server's original management IP:"
printf "\n"
echo "http://\$ETH0_PUBLIC_IPV4/"
printf "\n"
echo "The File Transfer portal is available at:"
printf "\n"
echo "http://\$ETH0_PUBLIC_IPV4:8080/"
printf "\n"

EOF

chmod +x /root/cleanup.sh

# Adding scripts in /etc/local.d ending with .start or .stop makes them run on startup or shutdown when the local service starts or stops
# The scripts must be executable: chmod +x script.stop
# The local service must be started for .stop scripts to run when the local service stops on reboot
# You can check the local service status with: rc-service local status
# For manual testing you can start/stop the local service with: rc-service local start  and  rc-service local stop
# This is useful so that when the user runs reboot it will automatically cleanup API objects

cp /root/cleanup.sh /etc/local.d/cleanup.sh.stop
rc-update add local
rc-service local start

cat /root/pci-device-info

printf "\n\n"
echo "The ISO installation environment is available at:"
printf "\n"
echo "http://$SERVER_IP/"
printf "\n"
echo "The File Transfer portal is available at:"
printf "\n"
echo "http://$SERVER_IP:8080/"
printf "\n"
echo "The instance is running in $([ -d /sys/firmware/efi ] && echo UEFI || echo BIOS) boot mode."
printf "\n\n"

if [ "$IOMMU_STATE" == "disabled" ]; then
    echo "WARNING: IOMMU is disabled in $([ -d /sys/firmware/efi ] && echo UEFI || echo BIOS) so PCI Passthrough will not work!"
    printf "\n"
fi


