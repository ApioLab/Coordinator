#!/bin/bash
currentFolder=$(pwd)
folderName=$(basename $(pwd))
gitStatus=$(git clone -q https://github.com/ApioLab/ApioOS ../${folderName}_new 2> /dev/null; echo $?)

log () {
    echo "$(date +%F\ %R:%S) >> $@" >> ./apio_updater.log
}

if [ "$gitStatus" -ne 0 ]; then
    log "git clone error"
    exit 1
else
    # copy files
    cp "../${folderName}_new/configuration/default.js" "../${folderName}_new/configuration/custom.js"

    cp -R "${currentFolder}/node_modules" "../${folderName}_new"
    cp -f "${currentFolder}/*.apio" "../${folderName}_new"
    cp -R "${currentFolder}/public/bower_components" "../${folderName}_new/public"
    rsync -aq "${currentFolder}/public/applications" "${folderName}_new/public" --exclude newfile --exclude 10 --exclude 9
    cp -R "${currentFolder}/public/users" "../${folderName}_new/public"
    cp -R "${currentFolder}/services/apio_logic" "../${folderName}_new/services"
    node -e '
    "use strict";
    const fs = require("fs");
    let oldConfig = undefined, newConfig = undefined;
    try {
        oldConfig = require("'${currentFolder}'/configuration/custom.js");
    } catch (ex) {
        oldConfig = require("'${currentFolder}'/configuration/default.js");
    }

    newConfig = require("'${folderName}'_new/configuration/custom.js");

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

    fs.writeFileSync("'${folderName}'_new/configuration/custom.js", "module.exports = " + JSON.stringify(newConfig, null, 4));'

    # md5 check
    md5NpmOld=($(md5sum ${currentFolder}/package.json))
    md5NpmNew=$(md5sum ../${folderName}_new/package.json)

    if [ "$md5NpmOld" -ne "$md5NpmNew" ]; then
        cd "../${folderName}_new"
        npmErr=$(npm install --unsafe-perm 2>&1 1>/dev/null)
        if [ ! -z "$npmErr" ]; then
            log "npm install error: ${npmErr}"
            exit 1
        fi
        cd "$currentFolder"
    fi

    md5BowerOld=($(md5sum ${currentFolder}/bower.json))
    md5BowerNew=$(md5sum ../${folderName}_new/bower.json)

    if [ "$md5BowerOld" -ne "$md5BowerNew" ]; then
        cd "../${folderName}_new"
        bowerErr=$(bower install --allow-root 2>&1 1>/dev/null)
        if [ ! -z "$bowerErr" ]; then
            log "bower install error: ${bowerErr}"
            exit 1
        fi
        cd "$currentFolder"
    fi

    # rename old folder
    mv "${currentFolder}" "${currentFolder}_old"

    # rename new folder
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
    }).map(function (service) {
        if (service === "dongle") {
            return "dongle_apio.js";
        } else if (service === "enocean") {
            return "dongle_enocean.js";
        } else if (service === "zwave") {
            return "dongle_zwave.js";
        } else if (service === "notification") {
            return "notification_mail_sms.js";
        } else {
            return i + ".js";
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

    for service in "${services[@]}"
    do
        kill -9 $(ps aux | grep ${service} | awk '{print $2}' | xargs)
    done

    kill -9 $(ps aux | grep app.js | awk '{print $2}' | xargs)

    # launching adjust for least check
    if [ -f "./apio_error.log" ]; then
        lines1=$(wc -l)
    else
        lines1=0
    fi

    cd "../${folderName}"
    forever start -s -c "node --expose_gc" app.js
    sleep 30

    if [ -f "./apio_error.log" ]; then
        lines2=$(wc -l)
    else
        lines2=0
    fi

    if [ "$lines1" -ne "$lines2" ]; then
        mv "../${folderName}" "../${folderName}_new"
        mv "${currentFolder}_old" "${currentFolder}"
        log $(cat ./apio_error.log)
        rm ./apio_error.log
    fi

    reboot

    exit 0
fi
