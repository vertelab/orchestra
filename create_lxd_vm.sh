#! /bin/bash

read -rp "Enter name of the new machine: " NAME
read -rp 'Enter ubuntu version: ' UBUNTUVERSION

SSHDIR="$HOME/.ssh"
PUBKEY=""

if [ -f "$SSHDIR/id_rsa.pub" ]; then
    PUBKEY="$SSHDIR/id_rsa.pub"
elif [ -f "$SSHDIR/id_ed25519.pub" ]; then
    PUBKEY="$SSHDIR/id_ed25519.pub"
fi

lxc launch ubuntu:"$UBUNTUVERSION" "$NAME"

lxc exec "$NAME" -- useradd -m -G sudo -s /bin/bash "$USER"
echo added user

echo "Please set a password for the user"
lxc exec "$NAME" -- passwd "$USER"

lxc exec "$NAME" -- mkdir /home/"$USER"/.ssh
echo added .ssh dir

if [ -n $PUBKEY ]; then
    lxc file push "$PUBKEY" "$NAME"/home/"$USER"/.ssh/authorized_keys
    lxc exec "$NAME" -- chown "$USER":"$USER" $HOME/.ssh/ -R
    echo added public key
fi

echo Adding ip address to host and config file 
VMIP=$(lxc exec "$NAME" -- ip a | grep -Po '\d{1,3}.\d{1,3}.\d{1,3}.\d{1,3}(?=\/24)')
if [[ ! $VMIP ]]; then
    echo -e "ERROR: Unable to get HostName\nAddition of ip address was NOT successful!"
    return 1
fi
if [ ! -f "${SSHDIR}/config" ]; then
    echo -e "\nHost $NAME\n  HostName $VMIP\n  ForwardAgent yes" > "$SSHDIR"/config
else
    echo -e "\nHost $NAME\n  HostName $VMIP\n  ForwardAgent yes" >> "$SSHDIR"/config
fi
echo -e "$VMIP $NAME" | sudo tee -a /etc/hosts
