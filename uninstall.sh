#!/bin/bash

# Check if the script is executed as root
if [ "$(id -u)" -ne 0 ]; then
    echo "Please execute this script as root."
    exit 1
fi

clear

echo "Uninstalling Dos Protections"

if [ -e '/etc/init.d/dos' ]; then
    echo; echo -n "Deleting init service..."
    UPDATERC_PATH=`whereis update-rc.d`
    if [ "$UPDATERC_PATH" != "update-rc.d:" ]; then
        service dos stop > /dev/null 2>&1
        update-rc.d dos remove > /dev/null 2>&1
    fi
    rm -f /etc/init.d/dos
    echo -n ".."
    echo " (done)"
fi

if [ -e '/etc/rc.d/dos' ]; then
    echo; echo -n "Deleting rc service..."
    service dos stop > /dev/null 2>&1
    rm -f /etc/rc.d/dos
    sed -i '' '/dos_enable/d' /etc/rc.conf
    echo -n ".."
    echo " (done)"
fi

if [ -e '/usr/lib/systemd/system/dos.service' ]; then
    echo; echo -n "Deleting legacy systemd service..."
    SYSTEMCTL_PATH=`whereis update-rc.d`
    if [ "$SYSTEMCTL_PATH" != "systemctl:" ]; then
        systemctl stop dos > /dev/null 2>&1
        systemctl disable dos > /dev/null 2>&1
    fi
    rm -f /usr/lib/systemd/system/dos.service
    echo -n ".."
    echo " (done)"
fi

if [ -e '/lib/systemd/system/dos.service' ]; then
    echo; echo -n "Deleting systemd service..."
    SYSTEMCTL_PATH=`whereis update-rc.d`
    if [ "$SYSTEMCTL_PATH" != "systemctl:" ]; then
        systemctl stop dos > /dev/null 2>&1
        systemctl disable dos > /dev/null 2>&1
    fi
    rm -f /lib/systemd/system/dos.service
    echo -n ".."
    echo " (done)"
fi

echo -n "Deleting script files..."
if [ -e '/usr/local/sbin/dos' ]; then
    rm -f /usr/local/sbin/dos
    echo -n "."
fi

if [ -d '/usr/local/dos' ]; then
    rm -rf /usr/local/dos
    echo -n "."
fi
echo " (done)"

if [ -e '/etc/logrotate.d/dos' ]; then
    echo -n "Deleting logrotate configuration..."
    rm -f /etc/logrotate.d/dos
    echo -n ".."
    echo " (done)"
fi

echo; echo "Uninstall Complete!"; echo
