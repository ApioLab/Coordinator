#!/bin/bash
git config --global user.email "alessandrochelli@gmail.com"
git config --global user.name "alechelli"
git stash
git pull
npm install
bower install --allow-root
