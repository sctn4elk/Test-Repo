#!/bin/bash
# node-red-installer.sh will install the necessary packages to get the Zymatic up and running with 
# node-red basic functions

#Copyright (c) 2021 Mike Howard All Rights Reserved


#REVISION HISTORY
#Developer: Mike Howard
#Build date: 4.30.2021
#Version: 1.0.0

echo "Installing Node Red"
bash <(curl -sL "https://raw.githubusercontent.com/node-red/linux-installers/master/deb/update-nodejs-and-nodered")
sudo systemctl enable nodered.service
node-red-pi --max-old-space-size=256 &
node-red-restart &

