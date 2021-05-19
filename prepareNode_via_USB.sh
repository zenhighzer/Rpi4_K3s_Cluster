echo scanning for nodes...

for node in $(grep -ao "/boot/.......[a-z0-9]/" /var/log/daemon.log |cut -d "/" -f 3|sort|uniq |grep -v overlays)

do echo checking node: $node

[ -f "$node"_checkfile ] || {
        echo node $node not provisioned yet
        echo creating checkfile for node $node
        touch "$node"_checkfile

        echo "preparing rootfs for node $node - this can take a while"
        sudo cp -ar /usb/nfs/rootfs/ /usb/nfs/disks/$node

        echo "preparing fstab for node $node"
        echo "proc            /proc           proc    defaults          0       0" |sudo tee /usb/nfs/disks/$node/etc/fstab
        echo "192.168.80.80:/usb/srv/tftp/boot/$node /boot nfs defaults,vers=4.1,proto=tcp 0 0" | sudo tee -a /usb/nfs/disks/$node/etc/fstab

        echo modifying node-hostname to $node
        echo $node |sudo tee /usb/nfs/disks/$node/etc/hostname

        echo creating temporary boot-directory for node $node
        sudo cp -ar /usb/srv/tftp/boot_template /usb/srv/tftp/boot/$(echo $node)_temp

        echo preparing boot-environment for node $node
        # following cmdline is raspi-default
        #echo "console=serial0,115200 console=tty1 root=/dev/nfs nfsroot=192.168.80.80:/usb/nfs/disks/$node,vers=4.1,proto=tcp rw ip=dhcp rootwait elevator=deadline" |sudo tee /usb/srv/tftp/boot/$(echo $node)_temp/cmdline.txt
        # following cmdline is k3s-optimized
        echo "console=serial0,115200 console=tty1 root=/dev/nfs nfsroot=192.168.80.80:/usb/nfs/disks/$node,vers=4.1,proto=tcp rw ip=dhcp rootwait elevator=deadline cgroup_memory=1 cgroup_enable=memory" | sudo tee /usb/srv/tftp/boot/$(echo $node)_temp/cmdline.txt


        echo copying ssh public key for user pi on node $node
        mkdir /usb/nfs/disks/$node/home/pi/.ssh
        chmod 700 /usb/nfs/disks/$node/home/pi/.ssh
        sudo cp -a /home/pi/.ssh/id_rsa.pub /usb/nfs/disks/$node/home/pi/.ssh/authorized_keys


        echo enabling sshd for node $node
        echo "" |sudo tee /usb/srv/tftp/boot/$(echo $node)_temp/ssh

        echo converting temporary boot-directory to final boot-directory for node $node
        sudo mv /usb/srv/tftp/boot/$(echo $node)_temp /usb/srv/tftp/boot/$node

        echo finished preparing environment for node $node
        touch "$node"_prepared
}

done

echo scanning for prepared nodes...

for node in $(ls *_prepared |cut -d "_" -f1)

        do echo trying to lookup/connect to node $node via ssh

        [ -f "$node"_readyssh ] ||  {
        echo test | nc $node 22
        [ $? -eq 0 ] && touch "$node"_readyssh
        }
done



echo scanning for reachable nodes...

for node in $(ls *_readyssh |cut -d "_" -f1)

        do echo checking checkfile
        [ -f "$node"_readyiscsi ] ||  {
        touch "$node"_readyiscsi

        echo creating iscsi-rancher-disk for node $node
        truncate -s 2G /usb/iscsi/"$node"_disk

        echo creating iscsi-target for node $node
        sudo tgt-setup-lun -n $node -d /usb/iscsi/"$node"_disk -b rdwr $(host "$node". |cut -d " " -f4)

        echo connect to node $node to install openscsi-tools
        ssh $node "sudo apt update && sudo apt install -y open-iscsi"

        echo connect to node $node for discovering iscsi-luns
        ssh $node "sudo iscsiadm --mode discoverydb --type sendtargets --portal 192.168.80.80 --discover"

        echo connect to node $node for login to iscsi-luns
        ssh $node "sudo iscsiadm --mode node --targetname iqn.2001-04.com.k8s1-"$node" --portal 192.168.80.80:3260 --login"

        echo connect to node $node for autostart isci-lun on next reboot
        ssh $node "sudo cat /etc/iscsi/nodes/iqn.2001-04.com.k8s1-$node/192.168.80.80,3260,1/default | sed s/'node.startup = manual'/'node.startup = automatic'/ |sudo tee /etc/iscsi/nodes/iqn.2001-04.com.k8s1-$node/192.168.80.80,3260,1/default_new"
        ssh $node "sudo mv /etc/iscsi/nodes/iqn.2001-04.com.k8s1-$node/192.168.80.80,3260,1/default /etc/iscsi/nodes/iqn.2001-04.com.k8s1-$node/192.168.80.80,3260,1/default_original"
        ssh $node "sudo mv /etc/iscsi/nodes/iqn.2001-04.com.k8s1-$node/192.168.80.80,3260,1/default_new /etc/iscsi/nodes/iqn.2001-04.com.k8s1-$node/192.168.80.80,3260,1/default"


        echo connect to node $node for login to partition iscsi-lun
        ssh $node "echo label: dos |sudo sfdisk /dev/sda"
        ssh $node "echo label-id: 0x5a0bbaea |sudo sfdisk /dev/sda"
        ssh $node "echo device: /dev/sda |sudo sfdisk /dev/sda"
        ssh $node "echo unit: sectors |sudo sfdisk /dev/sda"
        ssh $node "echo /dev/sda1 : start=        2048, size=     4192256, type=83 |sudo sfdisk /dev/sda"

        echo connect to node $node for creating filesystem on iscsi-lun
        ssh $node "sudo mkfs.ext4 -F /dev/sda1"

        echo connect to node for modifying fstab to automount iscsi-lun to /var/lib/rancher
        ssh $node "echo /dev/sda1 /var/lib/rancher ext4 _netdev 0 0 |sudo tee -a /etc/fstab"

        echo connect to node for mounting iscsi-lun to /var/lib/rancher
        ssh $node "sudo mkdir /var/lib/rancher"
        ssh $node "sudo mount /dev/sda1 /var/lib/rancher"

        touch "$node"_completed
    }
done



echo k3s-master:
[ -f k3smaster ] || {
        [ $(ls *_completed --sort=time -r 2>/dev/null | head -1|cut -d "_" -f1|wc -l) -gt 0 ] && {
                master=$(ls *_completed --sort=time -r |head -1|cut -d "_" -f1)
                echo $master > k3smaster
                echo master elected: $master
                ssh pi@$master "curl -sfL https://get.k3s.io | sh -"
                k3s_token=$(ssh $master "sudo cat /var/lib/rancher/k3s/server/node-token")
                echo $k3s_token > k3smaster_token
                }
}




echo k3s-slaves:
[ -f k3smaster_token ] && {
        for slave in $(ls *_completed |cut -d "_" -f1)
        do echo checking node $slave
         [ -f "$slave"_k3sslave ] || {
                [ $slave != $(cat k3smaster) ] && {
                touch "$slave"_k3sslave
                ssh $slave "curl -sfL https://get.k3s.io | K3S_URL=https://$(cat k3smaster):6443 K3S_TOKEN=$(cat k3smaster_token) sh -"
                }
        }
        done
}
