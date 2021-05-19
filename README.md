# Rpi4_K3s_Cluster
diskless boot, automatic: provisioning, installation k3s &amp; cluster-setup

1 x pi4 (deploy-master, ipv4-v6-router, dnsmasq, tftd-, nfs-, iscsi-server, copy of fresh-raspbian-boot and root-fs for provisioning new discovered pi´s): 2 x lan, sd-card & usb-storage for tftpd-boot/nfs and iscsi-data
3 x pi4 (k3s-master/slaves) -> use temporary sd-card to enable network-boot (15 seconds of work for each pi)

after setup just plugin power and ethernet to any raspberry pi.. no sd card needed, it will be provisioned automatically and create/joins k3s-cluster 



# raspi-cluster-deployment-master: hostname = k8s1 & ip = 192.168.80.80 on eth1 - dont forget do modify this script if using other hostname/ip 
# also acts as router ipv4/v6-router (radvd)
# needed software: dnsmasq nfs-kernel-server tgt nc radvd slurm sysstat host(command, should be already preinstalled)
# also do an ssh-keygen withouth passphrase
#
# needed directories: 
# - /nfs/disks -> new cluster-members will get new folders (system-root) inside of this directory -> should be mounted to usb-harddrive for better performance
# - /nfs/rootfs -> copied via "sudo cp -ar" from fresh raspian-sd-card
# 
# - /srv/tftp/boot ->  new cluster-members will get new folders (system-boot) inside of this directory
# - /srv/tftp/boot_template -> copied via "sudo cp -ar" from fresh raspian-sd-card
#
# (nfs) /etc/exports: 
# /nfs/disks *(rw,sync,no_subtree_check,no_root_squash)
# /srv/tftp/boot *(rw,sync,no_subtree_check,no_root_squash)
#
#
# dnsmasq.conf: 
# interface=eth1
# no-hosts
# dhcp-range=192.168.80.10,192.168.80.20,12h
# log-dhcp
# enable-tftp
# tftp-root=/srv/tftp/boot
# pxe-service=0,"Raspberry Pi Boot"
#
# /etc/crontab: 
# *  *    * * *   pi      /home/pi/bin/prepareNode.sh
#
# todo: 
# create iscsi-volumes, nfs-disks to external usb-harddrive for better performance 
# maybe create checkfiles in another directory (actually created in /home/pi), maybe subdirs? 
# better names for checkfiles 
# replacement of hardcoded stuff like hostname and ip´s with variables
# notes:
# copy rootfs-template from usb-stick to same usb-stick needs around 10min
# test -> copy rootfs-template from sd-storage to usb-stick
# maybe using tar.gz root/boot-templates
