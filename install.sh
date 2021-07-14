#!/bin/bash

# Check if the script is executed as root
if [ "$(id -u)" -ne 0 ]; then
    echo "Please execute this script as root."
    exit 1
fi

# Check for required dependencies
if [ -f "/usr/bin/apt-get" ]; then
    install_type='2';
    install_command="apt-get"
else
    install_type='0'
fi

packages='nslookup netstat ss ifconfig tcpdump tcpkill timeout awk sed grep grepcidr'

for dependency in $packages; do
    is_installed=`which $dependency`
    if [ "$is_installed" = "" ]; then
        echo "error: Required dependency '$dependency' is missing."
        if [ "$install_type" = '0' ]; then
            exit 1
        else
            echo -n "Autoinstall dependencies by '$install_command'? (n to exit) "
        fi
        read install_sign
        if [ "$install_sign" = 'N' -o "$install_sign" = 'n' ]; then
           exit 1
        fi
        eval "$install_command install -y $(grep $dependency config/dependencies.list | awk '{print $'$install_type'}')"
    fi
done

if [ -d "$DESTDIR/usr/local/dos" ]; then
    echo "Please Un-install the previous version first"
    exit 0
else
    mkdir -p "$DESTDIR/usr/local/dos"
fi

clear

if [ ! -d "$DESTDIR/etc/dos" ]; then
    mkdir -p "$DESTDIR/etc/dos"
fi

if [ ! -d "$DESTDIR/var/lib/dos" ]; then
    mkdir -p "$DESTDIR/var/lib/dos"
fi

echo; echo 'Install DoS Protections '; echo

if [ ! -e "$DESTDIR/etc/dos/dos.conf" ]; then
    echo -n 'Adding: /etc/dos/dos.conf...'
    cp config/dos.conf "$DESTDIR/etc/dos/dos.conf" > /dev/null 2>&1
    echo " (done)"
fi

if [ ! -e "$DESTDIR/etc/dos/ignore_ip.list" ]; then
    echo -n 'Adding: /etc/dos/ignore_ip.list...'
    cp config/ignore_ip.list "$DESTDIR/etc/dos/ignore_ip.list" > /dev/null 2>&1
    echo " (done)"
fi

if [ ! -e "$DESTDIR/etc/dos/ignore_host.list" ]; then
    echo -n 'Adding: /etc/dos/ignore_host.list...'
    cp config/ignore_host.list "$DESTDIR/etc/dos/ignore_host.list" > /dev/null 2>&1
    echo " (done)"
fi

# Install file script dos.sh "path: /usr/local/dos/dos.sh
echo -n 'Adding: /usr/local/dos/dos.sh...'
cp src/dos.sh "$DESTDIR/usr/local/dos/dos.sh" > /dev/null 2>&1
chmod 0755 /usr/local/dos/dos.sh > /dev/null 2>&1
echo " (done)"

echo -n 'Creating dos script: /usr/local/sbin/dos...'
mkdir -p "$DESTDIR/usr/local/sbin/"
echo "#!/bin/bash" > "$DESTDIR/usr/local/sbin/dos"
echo "/usr/local/dos/dos.sh \$@" >> "$DESTDIR/usr/local/sbin/dos"
chmod 0755 "$DESTDIR/usr/local/sbin/dos"
echo " (done)"

if [ -d /etc/logrotate.d ]; then
    echo -n 'Adding logrotate configuration...'
    mkdir -p "$DESTDIR/etc/logrotate.d/"
    cp src/dos.logrotate "$DESTDIR/etc/logrotate.d/dos" > /dev/null 2>&1
    chmod 0644 "$DESTDIR/etc/logrotate.d/dos"
    echo " (done)"
fi

echo;

# Install file service (Systemctl)
if [ -d /lib/systemd/system ]; then
    echo -n 'Setting up systemd service...'
    mkdir -p "$DESTDIR/lib/systemd/system/"
    cp src/dos.service "$DESTDIR/lib/systemd/system/" > /dev/null 2>&1
    chmod 0755 "$DESTDIR/lib/systemd/system/dos.service" > /dev/null 2>&1
    echo " (done)"

    # Check if systemctl is installed and activate service
    SYSTEMCTL_PATH=`whereis systemctl`
    if [ "$SYSTEMCTL_PATH" != "systemctl:" ] && [ "$DESTDIR" = "" ]; then
        echo -n "Activating dos service..."
        systemctl enable dos > /dev/null 2>&1
        systemctl start dos > /dev/null 2>&1
        echo " (done)"
    else
        echo "dos service needs to be manually started... (warning)"
    fi
elif [ -d /etc/init.d ]; then
    echo -n 'Setting up init script...'
    mkdir -p "$DESTDIR/etc/init.d/"
    cp src/dos.initd "$DESTDIR/etc/init.d/dos" > /dev/null 2>&1
    chmod 0755 "$DESTDIR/etc/init.d/dos" > /dev/null 2>&1
    echo " (done)"

    # Check if update-rc is installed and activate service
    UPDATERC_PATH=`whereis update-rc.d`
    if [ "$UPDATERC_PATH" != "update-rc.d:" ] && [ "$DESTDIR" = "" ]; then
        echo -n "Activating dos service..."
        update-rc.d dos defaults > /dev/null 2>&1
        service dos start > /dev/null 2>&1
        echo " (done)"
    else
        echo "dos service needs to be manually started... (warning)"
    fi
elif [ -d /etc/rc.d ]; then
    echo -n 'Setting up rc script...'
    mkdir -p "$DESTDIR/etc/rc.d/"
    cp src/dos.rcd "$DESTDIR/etc/rc.d/dos" > /dev/null 2>&1
    chmod 0755 "$DESTDIR/etc/rc.d/dos" > /dev/null 2>&1
    echo " (done)"

    # Activate the service
    echo -n "Activating dos service..."
    echo 'dos_enable="YES"' >> /etc/rc.conf
    service dos start > /dev/null 2>&1
    echo " (done)"
fi

echo; echo 'Installation has Completed!'
echo 'Config files are located at /etc/dos/'
echo
echo 'Please send in your comment or your problem to :'
echo 'zakumi54@gmail.com'
echo 'Thank you 3 time'
echo

exit 0
