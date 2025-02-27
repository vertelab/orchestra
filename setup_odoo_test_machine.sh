#!/bin/bash

ODOOVERSION=""
ODOOREPO=""
UBUNTUVERSION=""
SHAREPATH="/usr/share"
ODOOTOOLS="/etc/profile.d/odootools.sh"
ODOO_SERVER_CONF="/etc/odoo/odoo.conf"

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NOCOLOR='\033[0m'

VERSIONS=(8 9 10 11 12 13 14 15 16 17 18 19)
UBUNTUVERSIONS=(14.04 14.04 18.04 17.04 18.04 20.04 20.04 20.04 22.04 22.04 24.04 24.04)

usage() { echo "Usage: $0 [-b <odooversion>] [-p <odoorepo>]" 1>&2; exit 1;}

while getopts ":b:p:" option; do
    case $option in
        b) ODOOVERSION=${OPTARG} ;;
        p) ODOOREPO=${OPTARG} ;;
        :) echo "Option -$OPTARG requires an argument" >&2; usage ;;
        \?) echo "Invalid option: -$OPTARG" >&2; usage ;;
    esac
done

if [ -z "$ODOOVERSION" ] || [ -z "$ODOOREPO" ]; then
    echo "Both -v (Odoo Version) and -r (Odoo Repo) options are required" >&2
    usage
fi

for i in "${!VERSIONS[@]}"; do
    if [[ "${VERSIONS[$i]}" == "${ODOOVERSION}" ]]; then
        UBUNTUVERSION="${UBUNTUVERSIONS[$i]}"
        break
    fi
done

if [ -z "$UBUNTUVERSION" ]; then
    while true; do
        read -rp "The Odoo version you entered is not known to this script. Please enter which version of Ubuntu should be used?" UBUNTUVERSION
        if [ -n "${UBUNTUVERSION}" ]; then
            break
        fi
    done
fi

ODOOREPOPATH="$SHAREPATH/$ODOOREPO"
MACHINENAME="${ODOOVERSION}-${ODOOREPO}-$(date +%Y-%m-%d-%H-%M-%S)"
VERSION="$ODOOVERSION.0"
SAVEUBUNTU=false

echo "Creating Ubuntu ${UBUNTUVERSION} for Odoo ${ODOOVERSION}"
echo "Cheking if machine with Odoo ${ODOOVERSION} Alredy exsists"
sudo lxc launch "odoo${ODOOVERSION}" "${MACHINENAME}"
if [[ $? -ne 0 ]]; then
    sudo lxc launch ubuntu:"$UBUNTUVERSION" "$MACHINENAME"
    SAVEUBUNTU=true
fi

echo "Waiting for the machine to receive an IP address..."
sleep 5

if [[ -z "$(sudo which pip)" ]]; then
    echo -e "${YELLOW}No pip installd${NOCOLOR}"
    echo Installing pip for root...
    wget -O- https://bootstrap.pypa.io/get-pip.py | sudo python3
fi

if [ ! -d /root/.config ]; then
    sudo lxc exec "$MACHINENAME" -- mkdir /root/.config
fi

if [ ! -d /root/.config/pip ]; then
    sudo lxc exec "$MACHINENAME" -- mkdir /root/.config/pip
fi

echo "Fixing brake-system-pages"
sudo lxc exec "$MACHINENAME" -- bash -c "wget -O /root/.config/pip/pip.conf https://raw.githubusercontent.com/vertelab/orchestra/main/pip.conf" 

echo "Installing Odoo..."
sudo lxc exec "$MACHINENAME" -- bash -c "wget -O- https://raw.githubusercontent.com/vertelab/odootools/${VERSION}/install | bash" 

if ! lxc exec "$MACHINENAME" -- systemctl is-active odoo; then
    echo -e "${RED}Failed to install Odoo.${NOCOLOR}"
    exit 1
fi
echo -e "${GREEN}Odoo installd${NOCOLOR}"

if [ "$SAVEUBUNTU" ]; then
    echo Shutting down machine in order to save it. Please be patient...
    lxc stop "$MACHINENAME" --force
    echo "Waiting for machine to shut down..."
    sleep 5
    echo "Publishing machine"
    lxc publish "$MACHINENAME" --alias "odoo${ODOOVERSION}"
    echo "Starting machine again..."
    lxc start "$MACHINENAME"
    sleep 5
fi

echo "Cloning repo..."
if ! sudo lxc exec "$MACHINENAME" -- bash -c "sudo git clone -b $VERSION https://github.com/vertelab/$ODOOREPO.git $ODOOREPOPATH"; then
    echo -e "${RED}Faild to clone repo $ODOOREPO${NOCOLOR}"
    exit 1
fi

PYTHONREQ="$ODOOREPOPATH/requirements.txt"
ODOOEXTREQ="$ODOOREPOPATH/requirements.repo"

echo "Checking for odootools.sh..."
if [[ -z "$(sudo lxc exec ${MACHINENAME} -- cat ${ODOOTOOLS})" ]]; then
    echo -e "${YELLOW}No odootools.sh found${NOCOLOR}"
    echo "Installing odootools.sh..."
    sudo lxc exec "$MACHINENAME" -- bash -c "sudo wget -O $ODOOTOOLS https://raw.githubusercontent.com/vertelab/odootools/common/odootools.sh"
fi

echo "using odootools..."
sudo lxc exec "$MACHINENAME" -- bash -c "source $ODOOTOOLS && odooaddons && odoosetperm"

if [[ -n "$(sudo lxc exec ${MACHINENAME} -- cat ${ODOOEXTREQ})" ]]; then
    echo "Installing dependencies..."
    sudo lxc exec "$MACHINENAME" -- bash -c "source $ODOOTOOLS && odooreqclone"
else
    echo "No dependencies found."
fi

if [[ -n "$(sudo lxc exec ${MACHINENAME} -- cat ${PYTHONREQ})" ]]; then
    echo "Installing python dependencies..."
    sudo lxc exec "$MACHINENAME" -- sudo pip3 install -r "$PYTHONREQ"
else
    echo "No python dependencies found."
fi

ODOOMODULES=$(sudo lxc exec "$MACHINENAME" -- find "$ODOOREPOPATH" -mindepth 1 -maxdepth 1 -type d -not \( -name ".git" \) -printf '%f\n' | tr '\n' ',' | sed 's/,$//')
USERID=$(sudo lxc exec "$MACHINENAME" -- id -u "odoo")

sudo lxc exec "$MACHINENAME" --user "$USERID" -- bash -c "odoo -c ${ODOO_SERVER_CONF} --database ${ODOOREPO} --init ${ODOOMODULES} --stop-after-init --logfile /var/log/odoo/test-odoo-server.log"

CHECK=$(sudo lxc exec "$MACHINENAME" -- cat /var/log/odoo/test-odoo-server.log | grep "CRITICAL")

if [[ -z "$CHECK" ]]; then
    echo -e "${GREEN}Successfully installed and tested modules.${NOCOLOR}"
else
    echo -e "${RED}Failed to install and test modules.${NOCOLOR}"
fi
