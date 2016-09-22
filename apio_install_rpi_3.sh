#!/bin/bash
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root" 1>&2
    exit 1
else
    user=$(who am i | awk '{print $1}')
    #Installing Apio
    mkdir -p /data/db
    apt-get update
    #Setting MySQL root password, this way during the installation nothing will be asked
    debconf-set-selections <<< 'mysql-server mysql-server/root_password password root'
    debconf-set-selections <<< 'mysql-server mysql-server/root_password_again password root'
    #Installing Debian dependencies
    apt-get install -y git build-essential libpcap-dev libzmq-dev python-pip python-dev python3-pip python3-dev libkrb5-dev nmap imagemagick mongodb curl ntp htop hostapd udhcpd iptables libnl-genl-3-dev libssl-dev xorg libgtk2.0-0 libgconf-2-4 libasound2 libxtst6 libxss1 libnss3 libdbus-1-dev libgtk2.0-dev libnotify-dev libgnome-keyring-dev libgconf2-dev libasound2-dev libcap-dev libcups2-dev libxtst-dev libnss3-dev xvfb avahi-daemon usb-modeswitch modemmanager mobile-broadband-provider-info ppp wvdial mysql-server libudev-dev
    apt-get clean
    curl -sL https://deb.nodesource.com/setup_0.12 | bash -
    apt-get install -y nodejs
    apt-get clean
    npm install -g bower browserify forever

    #Installing OpenZWave
    wget https://github.com/ekarak/openzwave-debs-raspbian/raw/master/v1.4.79/libopenzwave1.3_1.4.79.gfaea7dd_armhf.deb
    wget https://github.com/ekarak/openzwave-debs-raspbian/raw/master/v1.4.79/libopenzwave1.3-dev_1.4.79.gfaea7dd_armhf.deb
    dpkg -i libopenzwave*.deb
    rm libopenzwave*.deb
    #

    #Cloning and install Apio
    sudo -u $user git clone "https://github.com/ApioLab/ApioOS.git"
    cd ApioOS
    sudo -u $user npm install
    sudo -u $user npm install nightmare@2.1
    sudo -u $user bower install
    cd ..
    #

    #Creating MySQL DB
    mysql --host=localhost --user=root --password=root -e "CREATE DATABASE IF NOT EXISTS Logs DEFAULT CHARACTER SET utf8 DEFAULT COLLATE utf8_general_ci"
    sed -i '/skip-external-locking/i event_scheduler = ON' /etc/mysql/my.cnf
    service mysql restart

    #Enabling avahi service
    sed -i 's/#host-name=foo/host-name=apio/' /etc/avahi/avahi-daemon.conf
    sed -i 's/#domain-name/domain-name/' /etc/avahi/avahi-daemon.conf

    #Creating start.sh
    sudo -u $user echo -e "#!/bin/bash\ncd /home/$user/ApioOS\nforever start -s -c \"node --expose_gc\" app.js" > start.sh

    #Install PhantomJS
    git clone https://github.com/aeberhardo/phantomjs-linux-armv6l.git
    cd phantomjs-linux-armv6l
    bunzip2 *.bz2
    tar xf *.tar
    mv phantomjs-1.9.0-linux-armv6l /usr/local/etc/phantomjs
    ln -sf /usr/local/etc/phantomjs/bin/phantomjs /usr/bin/phantomjs
    cd ..
    rm -R phantomjs-linux-armv6l

    #Making the Wi-Fi Hotspot
    echo -e "start 192.168.2.2\nend 192.168.2.254\ninterface wlan0\nremaining yes\nopt dns 8.8.8.8 8.8.4.4\nopt subnet 255.255.255.0\nopt router 192.168.2.1\nopt lease 864000" > /etc/udhcpd.conf
    sed -e '/DHCPD_ENABLED="no"/ s/^#*/#/' -i /etc/default/udhcpd
    ifconfig wlan0 192.168.2.1
    echo -e '\niface wlan0 inet static\naddress 192.168.2.1\nnetmask 255.255.255.0\n\nup iptables-restore < /etc/iptables.ipv4.nat' >> /etc/network/interfaces
    sed -e '/allow-hotplug wlan0/ s/^#*/#/' -i /etc/network/interfaces
    sed -e '/iface wlan0 inet manual/ s/^#*/#/' -i /etc/network/interfaces
    sed -e '/wpa-conf \/etc\/wpa_supplicant\/wpa_supplicant.conf/ s/^#*/#/' -i /etc/network/interfaces
    echo -e 'interface=wlan0\ndriver=nl80211\nssid=Hotspot Apio\nhw_mode=g\nchannel=6\nauth_algs=1\nwmm_enabled=0' > /etc/hostapd/hostapd.conf
    echo 'DAEMON_CONF="/etc/hostapd/hostapd.conf"' >> /etc/default/hostapd
    sh -c "echo 1 > /proc/sys/net/ipv4/ip_forward"
    echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf
    iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
    iptables -A FORWARD -i eth0 -o wlan0 -m state --state RELATED,ESTABLISHED -j ACCEPT
    iptables -A FORWARD -i wlan0 -o eth0 -j ACCEPT
    iptables -t nat -A POSTROUTING -o ppp0 -j MASQUERADE
    iptables -A FORWARD -i ppp0 -o wlan0 -m state --state RELATED,ESTABLISHED -j ACCEPT
    iptables -A FORWARD -i wlan0 -o ppp0 -j ACCEPT
    sh -c "iptables-save > /etc/iptables.ipv4.nat"
    update-rc.d hostapd enable
    update-rc.d udhcpd enable

    #Installing 3G key
    cd /usr/share/usb_modeswitch
    tar zxvf configPack.tar.gz
    rm configPack.tar.gz
    echo -e "# D-Link DWM-156 (Variant)\nDefaultVendor=0x2001\nDefaultProduct=0xa707\nTargetVendor=0x2001\nTargetProduct= 0x7d02\nMessageContent=\"5553424312345678000000000000061b000000020000000000000000000000\"" > /usr/share/usb_modeswitch/2001\:a707
    echo -e "[Dialer Defaults]\nInit1 = AT+CFUN=1\nInit2 = AT+CGATT?\nInit3 = AT+CGDCONT=1,\"IP\",\"ibox.tim.it\"\nStupid Mode = 1\nModem Type = Analog Modem\nISDN = 0\nPhone = *99***1#\nModem = /dev/ttyUSB0\nUsername = { }\nPassword = { }\nBaud = 115200" > /etc/wvdial.conf

    #Launch Xvfb
    sudo -u $user Xvfb -ac -screen scrn 1280x2000x24 :9.0 & > /dev/null
    sudo -u $user export DISPLAY=:9.0

    #Add services to rc.local
    lines_number=$(wc -l < /etc/rc.local)
    sed -i "$((lines_number-1)) a mongod --repair\nifup wlan0\nservice udhcpd restart\nbash /home/$user/start.sh" /etc/rc.local

    #Installaing cron for wvdial
    mkdir -p /var/spool/cron/crontabs
    echo -e "*/2 * * * * sudo node /home/$user/ApioOS/3GConnect.js\n0 4 * * * sudo reboot" > /var/spool/cron/crontabs/$user
    chown $user:crontab /var/spool/cron/crontabs/$user
    chmod 600 /var/spool/cron/crontabs/$user
    service cron restart

    answer="x"
    while [[ $answer != "y" && $answer != "n" ]]; do
        read -p "A reboot is required, wanna proceed? (y/n) " answer
        if [[ $answer != "y" && $answer != "n" ]]; then
            echo "Please type y or n"
        elif [[ $answer == "y" ]]; then
            reboot
        fi
    done

    exit 0
fi
