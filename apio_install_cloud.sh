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

    
    #Creating start.sh
    sudo -u $user echo -e "#!/bin/bash\ncd /home/$user/ApioOS\nforever start -s -c \"node --expose_gc\" app.js" > start.sh

    
    #Add services to rc.local
    lines_number=$(wc -l < /etc/rc.local)
    sed -i "$((lines_number-1)) a mongod --repair\nbash /home/$user/start.sh" /etc/rc.local

    
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
