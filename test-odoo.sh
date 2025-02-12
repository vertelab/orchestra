#!/bin/bash

ODOOVERSION=""
ODOOREPO=""
UBUNTUVERSION=""
SHAREPATH="/usr/share"
ODOOTOOLS="/etc/profile.d/odootools.sh"
BREAK-SYSTEM-PACKAGES="[global]
break-system-packages = true
"

usage() { echo "Usage: $0 [-v <odooversion>] [-r <odoorepo>] [-u <ubuntuversion]" 1>&2; exit 1;}

while getopts ":v:r:u:" option; do
    case $option in
        v) ODOOVERSION=${OPTARG} ;;
        r) ODOOREPO=${OPTARG} ;;
        u) UBUNTUVERSION=${OPTARG} ;;
        :) echo "Option -$OPTARG requires an argument" >&2; usage ;;
        \?) echo "Invalid option: -$OPTARG" >&2; usage ;;
    esac
done

if [ -z "$ODOOVERSION" ] || [ -z "$ODOOREPO" ]; then
    echo "Both -v (Odoo Version) and -r (Odoo Repo) options are required" >&2
    usage
fi

if [ -z "$UBUNTUVERSION" ]; then
    while true; do
        read -rp "Which version of ubuntu should be used? " UBUNTUVERSION
        if [ -n "${UBUNTUVERSION}" ]; then
            break
        fi
    done
fi

ODOOREPOPATH="$SHAREPATH/$ODOOREPO"

echo $ODOOREPOPATH

echo "Odoo Version: $ODOOVERSION"
echo "Odoo Repo: $ODOOREPO"
MACHINENAME="${ODOOVERSION}-${ODOOREPO}-$(date +%Y-%m-%d-%H-%M-%S)"
echo "$MACHINENAME"

sudo lxc launch ubuntu:"$UBUNTUVERSION" "$MACHINENAME"

echo "Waiting for the machine to receive an IP address..."
sleep 5

if [[ -z "$(sudo which pip)" ]]; then
    echo No pip installd
    echo Installing pip for root...
    wget -O- https://bootstrap.pypa.io/get-pip.py | sudo python3
fi

if [ ! -d /root/.config ]; then
    sudo lxc exec "$MACHINENAME" -- mkdir /root/.config
fi

if [ ! -d /root/.config/pip ]; then
    sudo lxc exec "$MACHINENAME" -- mkdir /root/.config/pip
fi

if [ -e /root/.config/pip/pip.conf ]; then
    sudo lxc exec "$MACHINENAME" -- bash -c "echo $BREAK-SYSTEM-PACKAGES >> pip.conf" 
else
    sudo lxc exec "$MACHINENAME" -- bash -c "echo $BREAK-SYSTEM-PACKAGES > pip.conf" 
fi

echo "Installing Odoo..."
sudo lxc exec "$MACHINENAME" -- bash -c "wget -O- https://raw.githubusercontent.com/vertelab/odootools/18.0/install | bash" 

if ! systemctl list-units --full -all | grep -Fq "odoo.service"; then
    echo Odoo not installed succefuly
    exit 1 
fi 
echo "Odoo installd"

echo "Cloning repo..."

VERSION="$ODOOVERSION.0"

if ! sudo lxc exec "$MACHINENAME" -- bash -c "sudo git clone -b $VERSION https://github.com/vertelab/$ODOOREPO.git $ODOOREPOPATH"; then
    echo "Faild to clone repo $ODOOREPO"
    exit 1
fi

PYTHONREQ="$ODOOREPOPATH/requirements.txt"
ODOOEXTREQ="$ODOOREPOPATH/requirements.repo"

echo "Checking for odootools.sh..."
if [ ! -e "$ODOOTOOLS" ]; then
    echo "No odootools.sh found"
    echo "Installing odootools.sh..."
    sudo lxc exec "$MACHINENAME" -- bash -c "sudo wget -O $ODOOTOOLS https://raw.githubusercontent.com/vertelab/odootools/common/odootools.sh"
fi

echo "using odootools..."
sudo lxc exec "$MACHINENAME" -- bash -c "source $ODOOTOOLS && odooaddons && odoosetperm && odoorestart"

if [ -e "$ODOOEXTREQ" ]; then
    sudo lxc exec "$MACHINENAME" -- bash -c "source $ODOOTOOLS && odooreqclone"
fi

if [ -e "$PYTHONREQ" ]; then
    sudo lxc exec "$MACHINENAME" -- sudo pip3 install -r "$PYTHONREQ"
fi

ODOOMODULES=$(sudo lxc exec "$MACHINENAME" -- find "$ODOOREPOPATH" -maxdepth 1 -type d | tr '\n' ',') 

sudo lxc exec "$MACHINENAME" -- su odoo -c "odoo -c $ODOO_SERVER_CONF --database $ODOOREPO --init $ODOOMODULES --stop-after-init"
