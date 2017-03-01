#!/bin/bash
git config user.email "alessandrochelli@gmail.com"
git config user.name "alechelli"
rm -R  public/applications/newfile/d5-XX
cp -f Identifier.apio Identifier.old.apio
git stash
git pull
cp -f Identifier.old.apio Identifier.apio
rm Identifier.old.apio

#Deleting previous wvdial configuration
f=$(grep -n _per /etc/rc.local | cut -d ':' -f1 | head -n 1)
l=$(grep -n wvdial /etc/rc.local | cut -d ':' -f1 | tail -n 1)
if [ ! -z "$f" -a ! -z "$l" ];then
    sed "${f},${l}d" -i /etc/rc.local
fi
#

npm install --unsafe-perm 2> npm_error.log
bower install --allow-root 2> bower_error.log

if [ -f "./adjust.js" ];then
    node ./adjust.js
fi

exit 0
