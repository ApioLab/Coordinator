#!/bin/bash
currentFolder=$(pwd)
folderName=$(basename $(pwd))
branchName=$(cat ${currentFolder}/.git/HEAD | rev | cut -d '/' -f1 | rev)
gitStatus=$(git clone -q -b ${branchName} https://github.com/ApioLab/ApioOS ../${folderName}_new 2> /dev/null; echo $?)

log () {
    echo "$(date +%F\ %R:%S) >> $@" >> ${currentFolder}/apio_updater.log
}

if [ "$gitStatus" -ne 0 ]; then
    log "git clone error"
    exit 1
else
    log "disabilito il cron"
    for file in $(ls /var/spool/cron/crontabs)
    do
        sed -i -e 's/.*relaunch_ppp.sh/#&/' /var/spool/cron/crontabs/${file}
    done
    service cron restart

    log "killo relaunch_ppp.sh se è in running"
    kill -9 $(ps aux | grep relaunch_ppp.sh | awk '{print $2}' | xargs)

    log "killo Apio"
    pkill node

    log "creo custom.js"
    cp "../${folderName}_new/configuration/default.js" "../${folderName}_new/configuration/custom.js"

    log "copio files .apio"
    cp -f "${currentFolder}"/*.apio "../${folderName}_new"
    log "copio applicazioni"
    rsync -aq "${currentFolder}/public/applications" "../${folderName}_new/public" --exclude newfile --exclude 10 --exclude 9
    log "copio utenti"
    cp -R "${currentFolder}/public/users" "../${folderName}_new/public"
    log "copio logiche"
    cp -R "${currentFolder}/services/apio_logic" "../${folderName}_new/services"

    log "modifico custom.js"
    node -e '
    "use strict";
    const fs = require("fs");
    let oldConfig = undefined, newConfig = undefined;
    try {
        oldConfig = require("'${currentFolder}'/configuration/custom.js");
    } catch (ex) {
        oldConfig = require("'${currentFolder}'/configuration/default.js");
    }

    newConfig = require("../'${folderName}'_new/configuration/custom.js");

    newConfig.database = oldConfig.database;
    newConfig.remote = oldConfig.remote;
    newConfig.type = oldConfig.type;

    if (oldConfig.sql) {
        newConfig.sql = oldConfig.sql;
    }

    if (oldConfig.http.hasOwnProperty("uri")) {
        newConfig.http = oldConfig.http;
    }

    Object.keys(oldConfig.dependencies[oldConfig.type]).forEach(function (service) {
        if (oldConfig.dependencies[oldConfig.type][service].hasOwnProperty("uri") && oldConfig.dependencies[oldConfig.type][service].hasOwnProperty("port")) {
            newConfig.dependencies[newConfig.type][service].uri = oldConfig.dependencies[oldConfig.type][service].uri;
            newConfig.dependencies[newConfig.type][service].port = oldConfig.dependencies[oldConfig.type][service].port;
        }
    });

    fs.writeFileSync("../'${folderName}'_new/configuration/custom.js", "module.exports = " + JSON.stringify(newConfig, null, 4));'

    log "lancio npm"
    cd "../${folderName}_new"
    npmErr=$(npm install --unsafe-perm --loglevel=error 2>&1 1>/dev/null)
    if [ "$(echo ${npmErr} | tr '\n' ';' | grep -c 'PhantomJS')" -gt "1" ]; then
        log "npm install error:" ${npmErr}
        exit 1
    fi
    cd "$currentFolder"

    log "lancio bower"
    cd "../${folderName}_new"
    bowerErr=$(bower install --allow-root --loglevel=error 2>&1 1>/dev/null)
    if [ ! -z "${bowerErr}" ]; then
        log "bower install error:" ${bowerErr}
        exit 1
    fi
    cd "$currentFolder"

    # rename old folder
    log "sposto cartella vecchia"
    mv "${currentFolder}" "${currentFolder}_old"

    # rename new folder
    log "sposto cartella nuova"
    mv "../${folderName}_new" "../${folderName}"

    # stopping services and app.js
    services=$(node -e '
    "use strict";
    let config = undefined;
    try {
        config = require("'${currentFolder}'/configuration/custom.js");
    } catch (ex) {
        config = require("'${currentFolder}'/configuration/default.js");
    }

    const services = Object.keys(config.dependencies[config.type]).filter(function (service) {
        return config.dependencies[config.type][service].startAs === "process";
    }).map(function (service) {
        if (service === "dongle") {
            return "dongle_apio.js";
        } else if (service === "enocean") {
            return "dongle_enocean.js";
        } else if (service === "zwave") {
            return "dongle_zwave.js";
        } else if (service === "notification") {
            return "notification_mail_sms.js";
        } else {
            return service + ".js";
        }
    });

    console.log(services);')

    # strip white space
    services=${services// /}
    # substitute , with space
    services=${services//,/ }
    # remove [ and ]
    services=${services##[}
    services=${services%]}
    # create an array
    eval services=(${services})

    log "killo app.js e servizi"
    for service in "${services[@]}"
    do
        kill -9 $(ps aux | grep ${service} | awk '{print $2}' | xargs)
    done

    kill -9 $(ps aux | grep app.js | awk '{print $2}' | xargs)

    # launching adjust for least check
    if [ -f "${currentFolder}/apio_error.log" ]; then
        lines1=$(wc -l)
    else
        lines1=0
    fi

    log "riavvio app.js e attendo"
    cd "../${folderName}"
    forever start -s -c "node --expose_gc" app.js
    sleep 30

    if [ -f "${currentFolder}/apio_error.log" ]; then
        lines2=$(wc -l)
    else
        lines2=0
    fi

    if [ "$lines1" -ne "$lines2" ]; then
        log "ho avuto un errore inaspettato quindi rimetto tutto apposto"
        mv "../${folderName}" "../${folderName}_new"
        mv "${currentFolder}_old" "${currentFolder}"
    fi

    log "installo pm2"
    npm install -g pm2
    log "installo pm2-logrotate"
    pm2 install pm2-logrotate@2.2.0
    log "modifico start.sh"
    sed -i -e 's/forever start -s -c "node --expose_gc" app.js/pm2 start --node-args="--expose_gc" app.js/' ${currentFolder}/../start.sh
    log "modifico rc.local"
    sed -i -e 's/^bash \/home\/pi\/start.sh$/sudo &/' /etc/rc.local

    reboot

    exit 0
fi
