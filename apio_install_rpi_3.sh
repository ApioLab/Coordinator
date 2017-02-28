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
    curl -sL https://deb.nodesource.com/setup_4.x | bash -
    apt-get install -y nodejs
    apt-get clean

    npm_exit_code=1
    while [[ $npm_exit_code -ne 0 ]]
    do
        npm install -g npm
        npm_exit_code=$(echo $?)
    done

    bower_exit_code=1
    while [[ $bower_exit_code -ne 0 ]]
    do
        npm install -g bower
        bower_exit_code=$(echo $?)
    done

    browserify_exit_code=1
    while [[ $browserify_exit_code -ne 0 ]]
    do
        npm install -g browserify
        browserify_exit_code=$(echo $?)
    done

    forever_exit_code=1
    while [[ $forever_exit_code -ne 0 ]]
    do
        npm install -g forever
        forever_exit_code=$(echo $?)
    done

    #Installing OpenZWave
    wget https://github.com/ekarak/openzwave-debs-raspbian/raw/master/v1.4.79/libopenzwave1.3_1.4.79.gfaea7dd_armhf.deb
    wget https://github.com/ekarak/openzwave-debs-raspbian/raw/master/v1.4.79/libopenzwave1.3-dev_1.4.79.gfaea7dd_armhf.deb
    dpkg -i libopenzwave*.deb
    rm libopenzwave*.deb
    #

    #Cloning and install Apio
    sudo -u $user git clone "https://github.com/ApioLab/ApioOS.git"
    cd ApioOS

    npm_exit_code_v2=1
    while [[ $npm_exit_code_v2 -ne 0 ]]
    do
        sudo -u $user npm install
        npm_exit_code_v2=$(echo $?)
    done

    bower_exit_code_v2=1
    while [[ $bower_exit_code_v2 -ne 0 ]]
    do
        sudo -u $user bower install
        bower_exit_code_v2=$(echo $?)
    done

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
    git clone https://github.com/ApioLab/phantomjs-2.1.1-linux-arm
    cd phantomjs-2.1.1-linux-arm
    bunzip2  phantomjs-2.1.1-linux-arm.tar.bz2
    tar xf phantomjs-2.1.1-linux-arm.tar
    mv phantomjs-2.1.1-linux-arm /usr/local/etc/phantomjs
    ln -sf /usr/local/etc/phantomjs/bin/phantomjs /usr/bin/phantomjs
    cd ..
    rm -R phantomjs-2.1.1-linux-arm

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

    #Add services to rc.local
    lines_number=$(wc -l < /etc/rc.local)
    sed -i "$((lines_number-1)) a mongod --repair\nifup wlan0\nservice udhcpd restart\nbash /home/$user/start.sh" /etc/rc.local

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
