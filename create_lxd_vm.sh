#! /bin/bash

read -rp "Enter name of the new machine: " NAME
read -rp 'Enter ubuntu version: ' UBUNTUVERSION

PUBKEY="$HOME/.ssh/id_rsa.pub"

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
