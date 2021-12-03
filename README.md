# metal-isometric-xepa

ISO installation environment for Equinix Metal

![windows-isometric-meme](/images/windows-isometric-meme.png)

## Overview

This project makes it possible to install any ISO of your choice on Equinix Metal instances. Windows 10? TrueNAS? NSX Edge? All the ISOs!!!

## How does it work?

TLDR: Custom iPXE + Rescue mode / Alpine Linux + KVM hypervisor + IOMMU / VFIO PCI Passthrough + GUI + Web Browser

Equinix Metal provides the option of deploying instances with the `Custom iPXE` Operating System which is effectively a bare metal node with empty local disks.

Once provisioned, we can then switch over to the `Rescue Mode` which reboots the server into an in-memory Alpine Linux environment.

Insine Alpine Linux, a set of packages are installed to provide a GUI interface with a web browser and KVM hypervisor.

A virtual machine is created that boots the ISO with the server local disk allocated to it along with the PCI device of your choice passed through in cases where you may need to install drivers.

Once the ISO installation is done, rebooting the machine will make it boot through the local disk which we wrote to via the VM earlier.

Profit???

## Guide

### Provision an Equinix Metal instance with Custom iPXE

Login to the Equinix Metal [console](https://console.equinix.com/), then click the `New Server` button to provision an instance.

![new-server](/images/new-server.png)

Select your deployment type such as on-demand.

Select the metro location that you will be deploying in, then select the server type of your choice.

![metro-server-selection](/images/metro-server-selection.png)

Under the Operating Systems section, choose `Custom iPXE`. For the iPXE Script URL field you can provide anything as we won't actually be using it. In my case i'm passing `http://boot.netboot.xyz`.

![custom-ipxe-selection](/images/custom-ipxe-selection.png)

At the Optional Settings section, there will be an option to configure IPs. If you leave the toggle unchecked, the instance will be deployed with a /31 public IPv4 subnet, /31 private IPv4 subnet, and a /127 public IPv6 subnet.

For many operating systems a /31 subnet size will work fine but there are cases where a /30 subnet is required at minimum such as for Microsoft Windows or VMware ESXi. If that is the case, you will need to [request a /30 Elastic IP subnet](https://metal.equinix.com/developers/docs/networking/reserve-public-ipv4s/#requesting-public-ipv4-addresses) and then use that subnet as the [instance management subnet](https://metal.equinix.com/developers/docs/networking/reserve-public-ipv4s/#provisioning-with-a-reserved-public-ipv4-subnet).

For this guide I will be installing Windows 10 so I will be using a /30 Elastic IP subnet for the instance management subnet. Here is what it would look like:

![configure-instance-ips](/images/configure-instance-ips.png)

Confirm your settings and click the `Deploy Now` button to start provisioning your server.

### Switch the instance to Rescue Mode

Once the Equinix Metal instance has completed provisioning, click on it so that you can view the server's overview page. On this page you will be able to see additional information such as the management subnets. We need to switch the instance to [Rescue Mode](https://metal.equinix.com/developers/docs/resilience-recovery/rescue-mode/) which you can do by clicking the `Server Actions` button on the top right, then select the `Rescue OS` option.

![switch-to-rescue-mode](/images/switch-to-rescue-mode.png)

You will notice that the Operating System now says `Alpine 3` as that is the Rescue OS. This will be temporary and will change back to `Custom iPXE` after getting out of the Rescue Mode.

While the instance is transitioning to Rescue Mode, you can monitor the node through the [Out-of-Band console](https://metal.equinix.com/developers/docs/resilience-recovery/serial-over-ssh/#using-sos) if you wish.

To access the Rescue Mode environment, you can either use the Out-of-Band console or [SSH](https://metal.equinix.com/developers/docs/accounts/ssh-keys/#connecting-with-ssh) into it through the public management IP address. The Rescue Mode environment should look like the following:

![rescue-mode](/images/rescue-mode.png)

### Run the ISO installation environment setup script

We need to install several packages to make the Rescue Mode environment ready for installing an ISO to the server. To do so, run the following commands to run the setup script:

```bash
wget https://raw.githubusercontent.com/enkelprifti98/metal-isometric-xepa/main/setup.sh
chmod +x setup.sh
./setup.sh
```

The script should only take less than a minute to complete depending on the speed of the system and package downloads. If it completed successfully, you should see the following webserver output:

![script-completed](/images/script-completed.png)

### Access the ISO installation environment

The simplest way to access the server is by pointing your local web browser to the public IPv4 address of the Equinix Metal instance. The web browser should show this page:

![novnc](/images/novnc.png)

You can also use the VNC client of your choice and point it to the public IPv4 address of the Equinix Metal instance.

In both cases, you will be prompted to connect and enter a password which will be `alpine`.

Once you have logged in, you will see the desktop UI. You may get a prompt about power savings but you can just close the window by click the `X` button on the top right corner of the prompt.

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

You will get a prompt asking how you would like to install the operating system. Choose the `Local install media (ISO image or CDROM)` option.

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

However, for other ISO images such as TrueNAS the detection may not work. You need to uncheck the `Automatically detect from the installation media / source` box and search for `generic` in the operating system field. Select the `Generic default (generic)` option. If your image is using a popular operating system under the hood such as Debian or Redhat, you can also choose those as the operating system instead of the generic option.

![virt-manager-generic-os](/images/virt-manager-generic-os.png)

After you have chosen your ISO file, click the `Forward` button. A prompt will appear saying that `The emulator may not search permissions for the path to the ISO file` and asking you to correct it now, click the `Yes` button.

Then you need to allocate the RAM and CPU amount to the VM. I personally use 4096 MB (4 GB) and 4 CPUs but feel free to adjust those to your preference.

![virt-manager-ram-cpu-settings](/images/virt-manager-ram-cpu-settings.png)

Click the `Forward` button.
