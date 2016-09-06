#!/bin/bash
git config --global user.email "alessandrochelli@gmail.com"
git config --global user.name "alechelli"
cp -f Identifier.apio Identifier.old.apio
git stash
git pull
cp -f Identifier.old.apio Identifier.apio
rm Identifier.old.apio
npm install
bower install --allow-root
