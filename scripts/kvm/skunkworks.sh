#!/bin/bash

# This script automates the setup of a Debian virtual machine on KVM.

# set -x

### variables

# script variables
TEMP_DIR="$(mktemp -d)"

# kvm variables
VM_CPU=2
VM_RAM=4096
VM_DISK=40
VM_USER="user"
VM_NAME="skunkworks"
VM_MAC="52:54:00:fd:3c:4a"

# github variables
GH_USER="korliaftis"

### reset

# countdown
for i in {5..1}; do
  echo -e "\033[0;95m$i\033[0m"
  sleep 1
done

# cleanup
virsh destroy ${VM_NAME} > /dev/null 2>&1
virsh undefine ${VM_NAME} --remove-all-storage > /dev/null 2>&1

### setup

# preseed.cfg
cat << EOF > ${TEMP_DIR}/preseed.cfg
#_preseed_V1

d-i debian-installer/locale string en_US
d-i keyboard-configuration/xkb-keymap select us

d-i netcfg/choose_interface select auto

d-i netcfg/get_hostname string unassigned-hostname
d-i netcfg/get_domain string unassigned-domain
d-i netcfg/hostname string ${VM_NAME}

d-i mirror/protocol string http
d-i mirror/country string manual
d-i mirror/http/hostname string deb.debian.org
d-i mirror/http/directory string /debian
d-i mirror/http/proxy string

d-i passwd/root-login boolean true
d-i passwd/make-user boolean true
d-i passwd/root-password password 123
d-i passwd/root-password-again password 123
d-i passwd/user-fullname string ${VM_USER}
d-i passwd/username string ${VM_USER}
d-i passwd/user-password password 123
d-i passwd/user-password-again password 123

d-i clock-setup/utc boolean true

d-i time/zone string Europe/Athens
d-i clock-setup/ntp boolean true

d-i partman-auto/method string regular
d-i partman-auto/choose_recipe select atomic

d-i partman-partitioning/confirm_write_new_label boolean true
d-i partman/choose_partition select finish
d-i partman/confirm boolean true
d-i partman/confirm_nooverwrite boolean true

d-i partman-partitioning/choose_label select gpt
d-i partman-partitioning/default_label string gpt

d-i apt-setup/disable-cdrom-entries boolean true

tasksel tasksel/first multiselect standard, ssh-server

popularity-contest popularity-contest/participate boolean false

d-i grub-installer/bootdev string default

d-i preseed/late_command string cp install.sh /target/tmp/ && chmod +x /target/tmp/install.sh && in-target /tmp/install.sh

d-i finish-install/reboot_in_progress note
EOF

# install.sh
cat << EOF > ${TEMP_DIR}/install.sh
#!/bin/bash

set -e

apt update && apt upgrade -y
apt install -y bash-completion ca-certificates apt-transport-https vim git curl jq gnupg unzip htop tree tmux nmap tcpdump ethtool strace

apt install -y sudo
usermod -a -G sudo ${VM_USER}
echo "${VM_USER} ALL=(ALL) NOPASSWD:ALL" | EDITOR='tee -a' visudo
visudo --check

echo 'export PS1="\[\e[37m\][\[\e[92m\]\w\[\e[37m\]] \[\e[0m\]"' >> /home/${VM_USER}/.bashrc
echo 'export PS1="\[\e[37m\][\[\e[91m\]\w\[\e[37m\]] \[\e[0m\]"' >> /root/.bashrc

su - ${VM_USER} -c "ssh-keygen -t rsa -b 4096 -N '' -f /home/${VM_USER}/.ssh/id_rsa"
su - ${VM_USER} -c "curl https://github.com/${GH_USER}.keys >> /home/${VM_USER}/.ssh/authorized_keys"
chmod 600 /home/${VM_USER}/.ssh/authorized_keys

curl -L https://download.docker.com/linux/debian/gpg | gpg --dearmor > /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" > /etc/apt/sources.list.d/docker.list
apt update && apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
usermod -aG docker ${VM_USER}
systemctl daemon-reload
systemctl enable docker.service

curl -s https://raw.githubusercontent.com/korliaftis/korliaftis.github.io/master/scripts/prometheus/node-exporter.sh | bash
EOF

# install
virt-install \
  --name ${VM_NAME} \
  --virt-type kvm \
  --osinfo detect=on,require=off \
  --location https://ftp.debian.org/debian/dists/bookworm/main/installer-amd64/ \
  --memory ${VM_RAM} \
  --vcpus ${VM_CPU} \
  --disk path=/var/lib/libvirt/images/${VM_NAME}.qcow2,size=${VM_DISK},bus=virtio,format=qcow2 \
  --network bridge=br0,model=virtio,mac=${VM_MAC} \
  --graphics none \
  --extra-args console=ttyS0 \
  --initrd-inject ${TEMP_DIR}/preseed.cfg \
  --initrd-inject ${TEMP_DIR}/install.sh

virsh autostart ${VM_NAME}
