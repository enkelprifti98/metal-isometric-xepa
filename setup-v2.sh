#!/bin/sh

# Run from Out-of-Band console
# wget -q -O setup-v2.sh https://raw.githubusercontent.com/enkelprifti98/metal-isometric-xepa/main/setup-v2.sh && chmod +x setup-v2.sh && ./setup-v2.sh

echo
echo "XEPA ISO INSTALLATION ENVIRONMENT"
echo

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

apk add --no-cache ca-certificates bash curl jq openssl sudo xvfb x11vnc xfce4 xfce4-terminal faenza-icon-theme bash procps nano git pciutils gparted gzip p7zip cpio tar unzip xarchiver ethtool mokutil gtk+3.0-dev \
--update


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
# VM xml config files are stored in /etc/libvirt/qemu

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

#PUBLIC_IP=$(curl -s https://metadata.platformequinix.com/metadata | jq -r ".network.addresses[] | select(.public == true) | select(.address_family == 4) | .address")

#nohup filebrowser -r /root -a $PUBLIC_IP -p 8080 > /dev/null 2>&1 &

mkdir /root/Downloads

clear

# Network Interface PCI information

NETWORK_PCI_LIST=""

#IFS=$'\n'
METADATA=$(curl -s metadata.packet.net/metadata)
INTERFACES_COUNT=$(echo $METADATA | jq '.network.interfaces | length')

if [ "$INTERFACES_COUNT" -gt  "2" ];then

   # get network port mac address for eth2 on 4 port servers
   MANAGEMENT_METADATA_MAC=$(echo $METADATA | jq -r '.network.interfaces[] | select(.name == "eth2") | .mac')
   ETH0_METADATA_MAC=$(echo $METADATA | jq -r '.network.interfaces[] | select(.name == "eth0") | .mac')

else

   # get network port mac address for eth1 on 2 port servers
   MANAGEMENT_METADATA_MAC=$(echo $METADATA | jq -r '.network.interfaces[] | select(.name == "eth1") | .mac')
   ETH0_METADATA_MAC=$(echo $METADATA | jq -r '.network.interfaces[] | select(.name == "eth0") | .mac')

fi

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

    # Get proper management interface by checking the metadata with the OS
    if [ "$MANAGEMENT_METADATA_MAC" == "$LOCAL_MAC" ]; then
        MANAGEMENT_IF_NAME=$LINE
    fi

    PCI_ID=$(grep PCI_SLOT_NAME /sys/class/net/$LINE/device/uevent | cut -d "=" -f2)


    # Add only the eth0 interface / NIC to the XEPA ISO VM

    if [ "$ETH0_METADATA_MAC" == "$LOCAL_MAC" ]; then
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

STORAGE_PCI_LIST=""

IFS=$'\n'
echo
echo "Local storage drives:"
echo

#SATA drives
for LINE in $(ls -l /sys/block/ | grep "sd" | awk '{print $9, $10, $11}')
do

PCI_ID=$(echo $LINE | cut -d "/" -f4)

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


lspci -D | grep $PCI_ID | sed 's#^#PCI BDF #'
DEVICE_PATH=$(echo $LINE | awk '{print $1}' | sed 's#^#/dev/#')
lsblk -p -o NAME,TYPE,SIZE,MODEL,TRAN,ROTA,HCTL,MOUNTPOINT $DEVICE_PATH | sed 's#NAME#PATH#' | sed 's#ROTA#DRIVE-TYPE#' | sed 's# 0 #SSD      #' | sed 's# 1 #HDD      #'
echo

done


#NVMe drives
for LINE in $(ls -l /sys/block/ | grep "nvme" | awk '{print $9, $10, $11}')
do

PCI_ID=$(echo $LINE | cut -d "/" -f5)

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

lspci -D | grep $PCI_ID | sed 's#^#PCI BDF #'
DEVICE_PATH=$(echo $LINE | awk '{print $1}' | sed 's#^#/dev/#')
lsblk -p -o NAME,TYPE,SIZE,MODEL,TRAN,ROTA,HCTL,MOUNTPOINT $DEVICE_PATH | sed 's#NAME#PATH#' | sed 's#ROTA#DRIVE-TYPE#' | sed 's# 0 #SSD      #' | sed 's# 1 #HDD      #'
echo

done


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

  PCI_MULTIFUNCTION_TEST=$(lspci -vvv -D -s $LINE | grep Function)

  if [ "$PCI_MULTIFUNCTION_TEST" == "" ]; then
      # echo "not multifunction capable"
      PCI_MULTI_FUNCTION=off
  else
      PCI_MULTI_FUNCTION=on
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

  PCI_MULTIFUNCTION_TEST=$(lspci -vvv -D -s $LINE | grep Function)

  if [ "$PCI_MULTIFUNCTION_TEST" == "" ]; then
      # echo "not multifunction capable"
      PCI_MULTI_FUNCTION=off
  else
      PCI_MULTI_FUNCTION=on
  fi
  
# There's no need to add network devices to the boot order unless you need it for troubleshooting
#  VIRT_INSTALL_PCI_DEVICES=$VIRT_INSTALL_PCI_DEVICES--host-device=$LINE$',boot.order='$NUM$' '
  VIRT_INSTALL_PCI_DEVICES=$VIRT_INSTALL_PCI_DEVICES$'--host-device='$LINE,address.type=pci,address.multifunction=$PCI_MULTI_FUNCTION,address.domain=0x$PCI_DOMAIN,address.bus=0x$PCI_BUS,address.slot=0x$PCI_SLOT,address.function=0x$PCI_FUNCTION$' '
  
done

echo "$VIRT_INSTALL_PCI_DEVICES"

# Passing a string of parameters as a variable to virt-install doesn't seem to work as it seems like a formatting issue
# It works by evaluating the content of the string as shell code

VIRT_INSTALL_PARAMS='virt-install --name xepa --description "XEPA ISO Installer VM" --os-variant=generic --arch x86_64 --machine q35 --sysinfo host --cpu host-passthrough --vcpus=8 --ram=30000 --import --nonetworks --serial pty,target.port=0 --serial pty,target.port=1 --tpm model=tpm-crb,type=emulator,version=2.0 --noreboot '

# Useful virt-install options
# --os-variant detect=off \
# --os-variant detect=on \
# --virt-type kvm \
# --machine q35  using q35 chipset instead of i440fx is required for PCIe support otherwise passing specific PCI IDs to the guest instead of getting random IDs like address.domain=0x$PCI_DOMAIN will not work

if [ -d /sys/firmware/efi ]; then
    VIRT_INSTALL_PARAMS=$VIRT_INSTALL_PARAMS$'--boot uefi '
fi

SECURE_BOOT_STATE=$(mokutil --sb-state | grep "SecureBoot")
# SecureBoot enabled  or  SecureBoot disabled

if [ "$SECURE_BOOT_STATE" == "SecureBoot enabled" ]; then
#    VIRT_INSTALL_PARAMS=$VIRT_INSTALL_PARAMS$'--boot loader=/usr/share/qemu/edk2-x86_64-secure-code.fd,loader.readonly=yes,loader.type=pflash '
#    VIRT_INSTALL_PARAMS=$VIRT_INSTALL_PARAMS$'--boot uefi,loader.secure=no '
    VIRT_INSTALL_PARAMS=$VIRT_INSTALL_PARAMS$'--boot loader.secure=yes '
elseif [ "$SECURE_BOOT_STATE" == "SecureBoot disabled" ];
    VIRT_INSTALL_PARAMS=$VIRT_INSTALL_PARAMS$'--boot loader.secure=no '
fi

echo "$VIRT_INSTALL_PARAMS$VIRT_INSTALL_PCI_DEVICES"

eval "$VIRT_INSTALL_PARAMS$VIRT_INSTALL_PCI_DEVICES"



INSTANCE_ID=$(echo $METADATA | jq -r .id)
echo $INSTANCE_ID
METRO=$(echo $METADATA | jq -r .metro)
echo $METRO
API_METADATA=$(curl -s -X GET -H "X-Auth-Token: $AUTH_TOKEN" "https://api.packet.net/devices/$INSTANCE_ID?include=project_lite")
PROJECT_UUID=$(echo $API_METADATA | jq -r .project_lite.id)
echo $PROJECT_UUID

        echo "Creating the XEPA-MANAGEMENT-VLAN..."
        sleep 1
        OUTPUT=$(curl -s "https://api.equinix.com/metal/v1/projects/$PROJECT_UUID/virtual-networks" \
                -X POST \
                -H "Content-Type: application/json" \
                -H "X-Auth-Token: $AUTH_TOKEN" \
                --data '{
                        "vxlan":3500,
                        "metro":"'${METRO}'",
                        "description":"xepa-management"
                }')
        sleep 1
        if (echo $OUTPUT | jq -e 'has("errors")' > /dev/null); then
                echo $OUTPUT | jq
        else
                echo "Here is the new VLAN..."
                echo "$OUTPUT" | jq
                VLAN_UUID=$(echo $OUTPUT | jq -r .id)
                echo "Done..."
        fi

        echo "Creating the Elastic IP Block..."
        sleep 1
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
                        "details":"xepa-management",
                        "tags":[]
                }')
        sleep 1
        if (echo $OUTPUT | jq -e 'has("errors")' > /dev/null); then
                echo $OUTPUT | jq
        else
                echo "Here is the new Elastic IP Block..."
                echo "$OUTPUT" | jq
                IP_UUID=$(echo $OUTPUT | jq -r .id)
                SERVER_IP=$(echo $OUTPUT | jq -r .address)
                NETMASK=$(echo $OUTPUT | jq -r .netmask)
                GATEWAY=$(echo $OUTPUT | jq -r .gateway)
                echo "Done..."
        fi

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
        else
                echo "Here is the new Metal Gateway..."
                echo "$OUTPUT" | jq -r '{ "Metal Gateway ID":.id, "Metro":.virtual_network.metro_code, "VLAN":.virtual_network.vxlan, "Subnet":.ip_reservation | "\(.network)/\(.cidr)", "Gateway IP":.ip_reservation.gateway}'
                echo "Done..."
        fi

if [ "$INTERFACES_COUNT" -gt  "3" ];then

   # get network port id for eth2 on 4 port servers
   NETWORK_PORT_ID=$(echo $API_METADATA | jq -r '.network_ports[] | select(.name == "eth2") | .id')

else

   # get network port id for eth1 on 2 port servers
   NETWORK_PORT_ID=$(echo $API_METADATA | jq -r '.network_ports[] | select(.name == "eth1") | .id')

fi

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
        else
                echo "Done..."
        fi

        echo "Attaching XEPA-MANAGEMENT-VLAN to the server..."
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

auto $MANAGEMENT_IF_NAME
iface $MANAGEMENT_IF_NAME inet static
    address $SERVER_IP
    netmask $NETMASK
EOF

ifup $MANAGEMENT_IF_NAME

ip route del default
ip route add default via $GATEWAY

#ifdown eth0 doesn't work because eth0 isn't defined in /etc/network/interfaces
ip link set eth0 down

nohup filebrowser -r /root -a $SERVER_IP -p 8080 > /dev/null 2>&1 &

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
