# metal-isometric-xepa

ISO installation environment for Equinix Metal

![windows-isometric-meme](/images/windows-isometric-meme.png)

## Overview

This project makes it possible to install any ISO of your choice on Equinix Metal instances. Windows 10? TrueNAS? NSX Edge? All the ISOs!!!

## How does it work?

TLDR: Custom iPXE + Rescue mode / Alpine Linux + KVM hypervisor + IOMMU / VFIO PCI Passthrough + GUI + Web Browser

Equinix Metal provides the option of deploying instances with the Custom iPXE Operating System which is effectively a bare metal node with empty local storage drives.

Once provisioned, we can then switch over to Rescue Mode which reboots the server into an in-memory Alpine Linux environment.

Inside Alpine Linux, a set of packages are installed to provide a GUI interface with a web browser and KVM hypervisor.

A virtual machine is created that boots the ISO with the server local disk allocated to it along with the PCI device of your choice passed through in cases where you may need to install drivers.

Once the ISO installation is done, rebooting the machine will make it boot through the local disk which we wrote to via the VM earlier.

Profit???

## Guide

## Contents

- [Provision an Equinix Metal instance with Custom iPXE](#provision-an-equinix-metal-instance-with-custom-ipxe)
- [Switch the instance to Rescue Mode](#switch-the-instance-to-rescue-mode)
- [Run the ISO installation environment setup script](#run-the-iso-installation-environment-setup-script)
- [Access the ISO installation environment](#access-the-iso-installation-environment)
- [Download the ISO](#download-the-iso)
- [Create the ISO installation Virtual Machine](#create-the-iso-installation-virtual-machine)
- [Add serial consoles to the Virtual Machine](#add-serial-consoles-to-the-virtual-machine)
- [Attach a PCI device to the Virtual Machine](#attach-a-pci-device-to-the-virtual-machine)
- [Install the Operating System](#install-the-operating-system)
- [Post installation configuration](#post-installation-configuration)
  - [Networking driver](#networking-driver)
  - [Serial console](#serial-console)
  - [Remote access](#remote-access)
- [Rebooting to the physical host](#rebooting-to-the-physical-host)
- [Troubleshooting](#troubleshooting)

### Provision an Equinix Metal instance with Custom iPXE

Login to the Equinix Metal [console](https://console.equinix.com/), then click the `New Server` button to provision an instance.

![new-server](/images/new-server.png)

Select your deployment type such as on-demand.

Select the metro location that you will be deploying in, then select the server type of your choice.

![metro-server-selection](/images/metro-server-selection.png)

Under the Operating Systems section, choose `Custom iPXE`. For the iPXE Script URL field you can provide anything as we won't actually be using it. In my case I'm passing the following URL:

```
http://boot.netboot.xyz
```

![custom-ipxe-selection](/images/custom-ipxe-selection.png)

At the Optional Settings section, there will be an option to configure IPs. If you leave the toggle unchecked, the instance will be deployed with a /31 public IPv4 subnet, /31 private IPv4 subnet, and a /127 public IPv6 subnet.

**For many operating systems a /31 subnet size will work fine but there are cases where a /30 subnet is required at minimum such as for Microsoft Windows or VMware ESXi. If that is the case, you will need to [request a /30 Elastic IP subnet](https://metal.equinix.com/developers/docs/networking/reserve-public-ipv4s/#requesting-public-ipv4-addresses) and then use that subnet as the [instance management subnet](https://metal.equinix.com/developers/docs/networking/reserve-public-ipv4s/#provisioning-with-a-reserved-public-ipv4-subnet).**

For this guide I will be installing Windows 10 so I will be using a /30 Elastic IP subnet for the instance management subnet. Here is what it would look like:

![configure-instance-ips](/images/configure-instance-ips.png)

Confirm your settings and click the `Deploy Now` button to start provisioning your server.

### Switch the instance to Rescue Mode

Once the Equinix Metal instance has completed provisioning, click on it so that you can view the server's overview page. On this page you will be able to see additional information such as the management subnets. We need to switch the instance to [Rescue Mode](https://metal.equinix.com/developers/docs/resilience-recovery/rescue-mode/) which you can do by clicking the `Server Actions` button on the top right, then select the `Rescue OS` option.

![switch-to-rescue-mode](/images/switch-to-rescue-mode.png)

You will notice that the Operating System now says `Alpine 3` as that is the Rescue OS. This will be temporary and will change back to `Custom iPXE` after getting out of the Rescue Mode.

While the instance is transitioning to Rescue Mode, you can monitor the node through the [Out-of-Band console](https://metal.equinix.com/developers/docs/resilience-recovery/serial-over-ssh/#using-sos) if you wish.

To access the Rescue Mode environment, you can either use the Out-of-Band console or [SSH](https://metal.equinix.com/developers/docs/accounts/ssh-keys/#connecting-with-ssh) into it through the management IP address. The Rescue Mode environment should look like the following:

![rescue-mode](/images/rescue-mode.png)

### Run the ISO installation environment setup script

We need to install several packages to make the Rescue Mode environment ready for installing an ISO to the server. To do so, run the following command to run the setup script:

```
curl -s https://raw.githubusercontent.com/enkelprifti98/metal-isometric-xepa/main/setup.sh | sh
```

The script should only take less than a minute to complete depending on the speed of the system and package downloads. If it completed successfully, you should see the following webserver output:

![script-completed](/images/script-completed.png)

### Access the ISO installation environment

The simplest way to access the server is by pointing your local web browser to the public IPv4 address of the Equinix Metal instance. The web browser should show this page:

![novnc](/images/novnc.png)

You can also use the VNC client of your choice and point it to the public IPv4 address of the Equinix Metal instance.

In both cases, you will be prompted to connect and enter a password which will be `alpine`.

Once you have logged in, you will see the desktop UI. You may get a prompt about the Power Manager Plugin but you can just close the window by clicking the `X` button on the top right corner of the prompt.

![desktop](/images/desktop.png)

### Download the ISO

We need to download the ISO first which will be Windows 10 for this guide. To do so, you can launch the Firefox web browser by clicking the browser icon on the dock at the bottom of the screen.

![launch-web-browser](/images/launch-web-browser.png)

You should see the Firefox browser window open. At this point you can proceed with downloading the ISO of your choice.

![firefox](/images/firefox.png)

If you want to monitor the download you can click the downward facing arrow on the top right corner of the firefox window. To see where the ISO file was downloaded click the folder icon on the right side of the download. Downloads should be under the `/root/Downloads` folder by default.

![iso-download](/images/iso-download.png)

### Create the ISO installation Virtual Machine

Once you have downloaded your ISO, you need to create a Virtual Machine so that you can install the Operating System to the local server storage.

Launch the Virtual Machine Manager by clicking the search icon on the dock at the bottom of the screen, then type `virtual machine manager` in the search field which should show the Virtual Machine Manager application as a search result. Double click on the application to start it.

![launch-virt-manager](/images/launch-virt-manager.png)

The Virtual Machine Manager application will look like the following image. Start the process of creating a Virtual Machine by clicking the monitor icon at the top left corner of the Virtual Machine Manager window.

![virt-manager](/images/virt-manager.png)

You will get a prompt asking how you would like to install the operating system. Choose the `Local install media (ISO image or CDROM)` option and click the `Forward` button.

![virt-manager-install-media](/images/virt-manager-install-media.png)

Then you will be asked to choose the ISO file. Click the `Browse...` button.

![virt-manager-browse-button](/images/virt-manager-browse-button.png)

A new window will appear to choose the storage volume, click the `Browse Local` button.

![virt-manager-browse-local-button](/images/virt-manager-browse-local-button.png)

A new window will appear to locate the ISO file. Go to the Downloads folder or anywhere else that your ISO file might be located in and select it as the ISO media.

![find-downloads-folder](/images/find-downloads-folder.png)

![select-iso-file](/images/select-iso-file.png)

Once you've selected your ISO file, at the bottom of the window there will be a field that automatically detects the Operating System.

In my case, Microsoft Windows 10 is detected successfully.

![virt-manager-windows-detected](/images/virt-manager-windows-detected.png)

However, for other ISO images the detection may not work. You need to uncheck the `Automatically detect from the installation media / source` box and search for `generic` in the operating system field. On the search results window, check the box for `Include end of life operating systems` and select the `Generic default (generic)` option. If your image is using a popular operating system under the hood such as Ubuntu or FreeBSD you could also choose those as the operating system profile instead of the generic option.

![virt-manager-generic-os](/images/virt-manager-generic-os.png)

After you have chosen your ISO file, click the `Forward` button. A prompt will appear saying that `The emulator may not have search permissions for the path to the ISO file` and asking you to correct it now, click the `Yes` button.

Then you need to allocate the RAM and CPU amount to the VM. I personally use 4096 MB (4 GB) and 4 CPUs but feel free to adjust those to your preference.

![virt-manager-ram-cpu-settings](/images/virt-manager-ram-cpu-settings.png)

Click the `Forward` button.

The next step is configuring storage for the VM. On the storage configuration window, choose the `Select or create custom storage` option. There is an empty field below the option where we have to set the local server storage disk device path.

![virt-manager-storage](/images/virt-manager-storage.png)

To look at the available local disks, open the terminal application at the dock on the bottom of the screen.

![launch-terminal](/images/launch-terminal.png)

Inside the terminal window, type `lsblk -p` and press `Enter`. It will show the list of local storage drives along with their full device path (`/dev/sdX` or `/dev/nvmeXn1`) and size.

![list-storage](/images/list-storage.png)

**Depending on the server type you may see NVMe storage drives as well but you cannot use them as the target for the bootable operating system that we will be installing since Equinix Metal servers boot in Legacy BIOS and to use NVMe drives as bootable targets requires UEFI.**

I recommend using the smallest available drive which in my case are `/dev/sdc` and `/dev/sdd`. For this guide I will be using `/dev/sdc`.

Type the `/dev/sdc` disk device path in the Virtual Machine Manager storage field and click the `Forward` button.

![virt-manager-storage-device-path](/images/virt-manager-storage-device-path.png)

On the last page, select the `Customize configuration before install` option and click the `Finish` button.

![virt-manager-customize-config-before-install](/images/virt-manager-customize-config-before-install.png)

A new overview window will appear where you can see the different hardware components of the virtual machine.

### Add serial consoles to the Virtual Machine

We need to add 2 serial console devices to the Virtual Machine so that we can enable it later after installing the Operating System. This is needed to make the Equinix Metal Out-of-Band console work.

Start adding the first serial console device by clicking the `+ Add Hardware` button on the bottom left corner of the window.

![virt-manager-add-hardware](/images/virt-manager-add-hardware.png)

On the left sidebar select the `Serial` category. On the right side leave everything as default and click the `Finish` button.

![virt-manager-add-serial-console-device](/images/virt-manager-add-serial-console-device.png)

Repeat this process once again to add the second serial console device.

You should see 2 serial devices on the VM overview sidebar once you have added them.

![virt-manager-add-serial-console-devices](/images/virt-manager-add-serial-console-devices.png)

### Attach a PCI device to the Virtual Machine

**Note: This step is optional and may not be possible on certain / legacy server types that do not support IOMMU / VFIO PCI Passthrough properly such as the [c3.small.x86](https://github.com/dlotterman/metal_code_snippets/blob/main/metal_configurations/c3_small_x86/c3_small_x86.md). If the host does not support IOMMU or has not been configured properly, virt-manager will throw errors when starting the VM with PCI devices attached. Check with the Equinix Metal support team to verify that the server BIOS settings for AMD-Vi / Intel VT-d / IOMMU have been enabled.**

The next step is to pass the physical networking PCIe card to the Virtual Machine which is done through IOMMU / VFIO PCI Passthrough. This is helpful in cases where the original ISO image may not include the drivers needed for the network card so passing the physical device to the VM allows us to install the drivers through the internet provided to the virtual machine.

To do this, click the `+ Add Hardware` button on the bottom left corner of the window and a new one will appear.

![virt-manager-add-hardware](/images/virt-manager-add-pci-hardware.png)

On the left sidebar select the `PCI Host Device` category. On the right side you will see a large list of different PCI devices so you will need to find the networking card. Typically there will be `Ethernet controller` in the name of the PCI device so look for that.

```
domain number : bus number : device number : function number ... ... Ethernet Controller ... (interface ethX)
```

Once you have found it you will see 2 or 4 devices with the same name which represent each individual card. Equinix Metal instances typically come with 2 or 4 networking ports. If you scroll horizontally to the right side you will see `(interface eth0)` and `(interface eth1)`. This is also denoted by the PCI device function number at the beginning of the line so in my case it looks like the following:

```
0000:41:00:0 ... Ethernet Controller ... (interface eth0)
0000:41:00:1 ... Ethernet Controller ... (interface eth1)
```

**You cannot use the first device / interface eth0 as that is being used by the Rescue Mode environment for internet access. Therefore you need to choose any other interface so I will be using the second PCI device network card or interface eth1.**

![virt-manager-pci-device](/images/virt-manager-pci-device.png)

Once you have selected the networking PCI device, click the `Finish` button.

### Install the Operating System

On the VM overview window click the `Begin Installation` button on the top left corner of the window to start the virtual machine.

![virt-manager-begin-installation](/images/virt-manager-begin-installation.png)

A new window will appear with a video console of the Virtual Machine which should show the ISO image installer. You can maximize the window by clicking the square button on the top right corner of the window.

![virt-manager-maximize-window](/images/virt-manager-maximize-window.png)

At this point you can proceed with the installation process and you will notice that the local server disk we allocated earlier will appear as an installation target option.

![windows-installation-storage-selection](/images/windows-installation-storage-selection.png)

Once the installation has completed the VM will reboot into the operating system that was written to the local server disk.

![windows-desktop](/images/windows-desktop.png)

### Post installation configuration

After the operating system has been installed there are a few things to keep in mind before rebooting over to the physical host that will be running the operating system.

#### Networking driver

We need to make sure that the operating system has a working driver for the networking card so the server can get internet access and be managed remotely.

In some cases the operating system will already include a working driver as part of the vanilla ISO image installation.

If the OS does not contain the driver as part of the ISO image, it may be able to install the driver automatically through the internet. If not, you will need to download the driver manually through the networking card vendor driver download web pages as long as they support your operating system.

In the case of Microsoft Windows 10, the ISO image does not include drivers for my servers' networking card so I will be installing the driver through Windows Update via the internet. Looking at Device Manager, you will see the `Ethernet Controller` device that has no driver installed. That is the physical server PCI networking card that we passed to the VM.

![windows-device-manager-missing-nic-driver](/images/windows-device-manager-missing-nic-driver.png)

When we check windows update, there is an optional driver ready to be downloaded over the internet for our Intel Ethernet network card.

![windows-update-nic-driver-download](/images/windows-update-nic-driver-download.png)

Once the driver has been downloaded and installed, you will now notice in Device Manager that the physical networking card adapter is ready. The other Intel Gigabit network adapter is a virtual network adapter emulated by the virtual machine hypervisor that provides internet access to the VM.

![windows-device-manager-nic-ready](/images/windows-device-manager-nic-ready.png)

#### Serial console

The Equinix Metal Out-of-Band console is helpful in situations where the instance does not have internet access so it's a good idea to enable your operating system for serial console output.

More specifically, the Out-of-Band console uses the `COM2` serial port (I/O port `0x2F8`, IRQ 3) with a baud rate of `115200`, 8 data bits, no parity, and 1 stop bit.

In some cases, the operating system may have an option to enable the serial console through the GUI. If not, you may be able to do it through the following methods or other ways. Depending on how the OS starts the serial port numbering, you may need to set it as port 1 or port 2 if they start from 0 or not.

The standard edition of Windows does not support serial console output but if you're running Windows Server edition, we can enable Emergency Management Services (EMS) redirection with the following commands ran in Command Prompt as an Administrator:

```
bcdedit /bootems {default} ON
bcdedit /ems {current} ON
bcdedit /emssettings EMSPORT:2 EMSBAUDRATE:115200
```

![windows-enable-ems-serial-console](/images/windows-enable-ems-serial-console.png)

For Linux based operating systems, you can typically enable serial console output through the GRUB bootloader options found in `/etc/default/grub`. There you can add the following:

```
GRUB_DEFAULT=0
#GRUB_TIMEOUT_STYLE=hidden
GRUB_TIMEOUT=3
GRUB_CMDLINE_LINUX="console=tty0 console=ttyS1,115200n8"
GRUB_TERMINAL="serial console"
GRUB_SERIAL_COMMAND="serial --unit=1 --speed=115200 --word=8 --parity=no --stop=1"
```

Once you've edited the GRUB config file, you can apply the change with `update-grub`.

For BSD based operating systems you should be able to add serial console support by editing the `/boot/loader.conf` bootloader configuration file. Add the following to the config file:

```
boot_multicons="YES"
boot_serial="YES"
comconsole_speed="115200"
console="comconsole,vidconsole"
comconsole_port=0x2F8
```

Restart the virtual machine after you have configured the serial console settings inside the operating system for them to take effect.

To confirm that you have configured serial console output properly inside the operating system, you can open the terminal shell and run the following command:

```
virsh console win10 serial1
```

where `win10` is the name of my virtual machine. In your case the name of the VM may be different so replace it with your VM's name. You can see the VM name at the top of the running VM window.

![virt-manager-vm-name](/images/virt-manager-vm-name.png)

Note that `serial1` is the alias name of the second serial device (`Serial 2`) we added to the VM which corresponds to `COM2`. If you need to double check the alias name you can do so by viewing the XML settings of the serial device and look for `<alias name="serial1"/>`. The `Serial 2` device should also be using port 1 in `<target type="isa-serial" port="1">`.

On the other hand, the `Serial 1` device has alias name of `<alias name="serial0"/>` and is using port 0 in `<target type="isa-serial" port="0">` which corresponds to `COM1` or `0x3F8`. We need to be using the second serial device/port instead since that is what Equinix Metal uses for the Out-of-Band console.

You should be able to see output and also send keyboard input to the VM through the serial console. If you're not able to see any output you need to go back and adjust the operating system configuration.

#### Remote access

After we reboot over to the physical host booting from the local disk that has our installed operating system, we need to be able to access it remotely through its IP address. Remote access will depend on the operating system but typically it will either be RDP for Windows and SSH for almost everything else.

In windows, we can enable RDP in the settings app:

![windows-enable-remote-desktop](/images/windows-enable-remote-desktop.png)

For other operating systems, you need to install or enable the SSH server.

### Rebooting to the physical host

Once we have completed the post installation steps, we can reboot over to the physical host.

Shut down the virtual machine and close all running applications. Then disconnect from the VNC console or close the web browser window.

Go to the Equinix Metal console server overview page, click the `Server Actions` button and select the `Reboot` action.

![post-install-reboot-server](/images/post-install-reboot-server.png)

While the server is rebooting, you can monitor its progress through the [Out-of-Band console](https://metal.equinix.com/developers/docs/resilience-recovery/serial-over-ssh/#using-sos).

If you see any storage drive missing or filesystem mounting related errors in the Out-of-Band console, it could potentially mean that the Operating System does not detect the underlying storage drives / controller. Try installing the OS in a different drive type under a different HBA / storage controller. For troubleshooting, you could also [attach the PCI storage controller](#attach-a-pci-device-to-the-virtual-machine) to the VM inside the ISO installation environment to verify if the OS can detect the drives or not.

Once the server has rebooted succesfully, you should be able to access it via RDP / SSH through its IP address or the Out-of-Band console.

![windows-rdp-session](/images/windows-rdp-session.png)

In many cases the operating system will automatically configure the network through DHCP for the first network interface only. It's recommended to configure LACP bonding for the server's network interfaces if the operating system supports it. If you need to configure the network interfaces statically, the management subnet information can be found in the Equinix Metal portal instance overview page and for DNS servers you can use the following:

```
Primary   DNS Server: 147.75.207.207
Secondary DNS Server: 147.75.207.208
```

At this point you're all set!

### Troubleshooting

In the case that you reboot over to the physical host and things such as the Out-of-Band console or remote access over the internet are not working, you can go back to the VM environment to troubleshoot.

To do so, switch the server instance back to [Rescue Mode](#switch-the-instance-to-rescue-mode). Then [run the ISO installation environment setup script](#run-the-iso-installation-environment-setup-script) and [access the ISO installation environment](#access-the-iso-installation-environment) through your web browser or VNC client.

Once you're back in the rescue GUI environment, launch the Virtual Machine Manager by clicking the search icon on the dock at the bottom of the screen, then type `virtual machine manager` in the search field which should show the Virtual Machine Manager application as a search result. Double click on the application to start it.

![launch-virt-manager](/images/launch-virt-manager.png)

Start the process of creating a Virtual Machine by clicking the monitor icon at the top left corner of the Virtual Machine Manager window.

![virt-manager](/images/virt-manager.png)

You will get a prompt asking how you would like to install the operating system. This time we will choose the `Import existing disk image` option and click the `Forward` button.

![virt-manager-import-disk-image](/images/virt-manager-import-disk-image.png)

Then you need to provide the local storage device path where the operating system was installed. This should be the same one that we used earlier which in my case was `/dev/sdc` but you can double check in the terminal with `lsblk -p` or `fdisk -l` which will show several partitions under one of the storage drives.

![check-os-drive](/images/check-os-drive.png)

Search for your operating system or `generic` in the operating system field. On the search results window, check the box for `Include end of life operating systems` and select your specific OS or the `Generic default (generic)` option if nothing matches your OS. If your image is using a popular operating system under the hood such as Debian or Redhat, you can also choose those as the operating system instead of the generic option.

You can proceed with the rest of the VM hardware configuration settings and select the `Customize configuration before install` option and click the `Finish` button.

A new overview window will appear where you can see the different hardware components of the virtual machine. Add the [serial consoles](#add-serial-consoles-to-the-virtual-machine) and the [PCI networking card](#attach-a-pci-device-to-the-virtual-machine) to the virtual machine.

Once you have configured the VM settings you can click the `Begin Installation` button to start the VM. You can refer to the following sections of the guide to troubleshoot:

- [Post installation configuration](#post-installation-configuration)
  - [Networking driver](#networking-driver)
  - [Serial console](#serial-console)
  - [Remote access](#remote-access)

After you're done troubleshooting, you can [reboot back to the physical host](#rebooting-to-the-physical-host).
