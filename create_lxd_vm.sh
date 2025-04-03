#! /bin/bash

read -rp "Enter name of the new machine: " NAME
read -rp 'Enter ubuntu version: ' UBUNTUVERSION

SSHDIR="$HOME/.ssh"
PUBKEY="$SSHDIR/id_rsa.pub"

sudo lxc launch ubuntu:"$UBUNTUVERSION" "$NAME" -d root,size=20GiB --vm

echo waiting...
sleep 30

sudo lxc exec "$NAME" -- useradd -m -G sudo -s /bin/bash "$USER"
echo added user

echo "Please set a password for the user"
sudo lxc exec "$NAME" -- passwd "$USER"

sudo lxc exec "$NAME" -- mkdir /home/"$USER"/.ssh
echo added .ssh dir

sudo lxc file push "$PUBKEY" "$NAME"/home/"$USER"/.ssh/authorized_keys
sudo lxc exec "$NAME" -- chown "$USER":"$USER" $HOME/.ssh/ -R
echo added public key

echo Adding ip address to host and config file 
VMIP=$(sudo lxc exec "$NAME" -- ip a | grep -Po '\d{1,3}.\d{1,3}.\d{1,3}.\d{1,3}(?=\/24)')
if [ ! -d "${SSHDIR}/config" ]; then
    echo -e "\nHost $NAME\n  HostName $VMIP\n  ForwardAgent yes" > "$SSHDIR"/config
else
    echo -e "\nHost $NAME\n  HostName $VMIP\n  ForwardAgent yes" >> "$SSHDIR"/config
fi
echo -e "$VMIP $NAME" | sudo tee -a /etc/hosts
