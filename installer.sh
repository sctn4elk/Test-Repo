#!/bin/bash
# installer.sh will install the necessary packages to get the Zymatic up and running with basic functions

# Copyright (c) 2021 Mike Howard All Rights Reserved

# Launch installer with: "bash installer.sh"

# REVISION HISTORY
# Developer: Mike Howard
# Build date: 4.30.2021
# Version: 1.0.0


#VERSION SPECIFIC CONSTANTS
DEBIAN="buster"
FLOW="Zymatic_v2.5_5.23.2021.json"
ZYMATICRECIPE="Zymatic_Test_Recipe.xml"

#update the Raspberry Pi
echo "Updating the Raspberry Pi"
sudo apt update
sudo apt full-upgrade

# Install misc packages
#******************************************************************************
#PACKAGES=""
#sudo apt install $PACKAGES -y
sudo apt install build-essential git
#sudo apt install ufw
#sudo ufw enable

#add 1 wire support
#******************************************************************************
echo "Adding 1-Wire Support on GPIO 4"
sudo sed -i '/^\[all\].*/a dtoverlay=w1-gpio' /boot/config.txt

#install node-red
#******************************************************************************
read -n 1 -s -r -p "Do you want to install node-red? [y/n]: " userinput
if [ "$userinput" = "y" ]
then 
	echo ""
	echo "Retrieving Node-Red Installer" 
	wget -L https://raw.githubusercontent.com/sctn4elk/Test-Repo/main/node-red-installer.sh -P /home/pi
	sudo chmod +x node-red-installer.sh
	
	echo "Launching Node-Red Installer" 
	bash node-red-installer.sh

	echo "Checking for node-red" 
	while ! pgrep -u pi node\-red
		do
		sleep 1s 
	done
	echo "Node-red started"

	#switch to node-red directory
	cd $HOME/.node-red

	#install required node-red nodes 
	npm install node-red-dashboard
	npm install node-red-contrib-ui-led 
	npm install node-red-contrib-sensor-ds18b20  
	npm install node-red-contrib-queue-gate 
	npm install node-red-contrib-pid 
	npm install node-red-node-pi-gpio 
	npm install node-red-contrib-mytimeout 
	npm install node-red-contrib-fs 
	npm install node-red-contrib-influxdb
	npm install node-red-contrib-timeprop
	npm update socket.io --depth 2
	npm install xmlhttprequest-ssl
	npm install socket.io
	npm audit fix
else
	echo ""
	echo "Skipping node-red installation"
fi

#install mosquitto
#******************************************************************************
read -n 1 -s -r -p "Do you want to install mosquitto? [y/n]: " userinput
if [ "$userinput" = "y" ]
then 
	echo ""
	echo "Installing the MQTT Service"
	sudo apt install mosquitto mosquitto-clients

	## Set up Mosquitto security
	echo "mqtt:changeme" > pwfile
	mosquitto_passwd -U pwfile
	sudo mv pwfile /etc/mosquitto/

	CONFIG="/etc/mosquitto/mosquitto.conf"
	PWFILE="/etc/mosquitto/pwfile"
	
	# If a line containing "allow_anonymous" exists
	if grep -Fq "allow_anonymous" $CONFIG
	then
		# security file present...
		echo "Modifying security"
		sudo sed -i 's|^allow_anonymous.*|allow_anonymous false|g' $CONFIG
		sudo sed -i 's|^password_file.*|password_file '"$PWFILE"'|g' $CONFIG
	else
		# Create the definition
		echo "Creating security"
		sudo sed -i '|^include_dir.*|i allow_anonymous false' $CONFIG
		sudo sed -i '|^allow_anonymous.*|a password_file '"$PWFILE"'' $CONFIG
	fi

	#restart the mosquitto service
	sudo /etc/init.d/mosquitto restart
else
	echo ""
	echo "Skipping mosquitto installation"
fi

#install Influx DB
#******************************************************************************
read -n 1 -s -r -p "Do you want to install influxdb? [y/n]: " userinput
if [ "$userinput" = "y" ]
then 
	echo ""
	echo "Installing the InFlux Database service"
	wget -qO- https://repos.influxdata.com/influxdb.key | sudo apt-key add -
	lsb_release -a
	echo "deb https://repos.influxdata.com/debian $DEBIAN stable" | sudo tee /etc/apt/sources.list.d/influxdb.list

	sudo apt update
	sudo apt install influxdb

	sudo systemctl unmask influxdb
	sudo systemctl enable influxdb
	sudo systemctl start influxdb
	
	echo "Checking for influxdb" 
	while ! pgrep -u influxdb influxd
		do
		sleep 1s 
	done
	echo "InfluxDB started"
	
	#sudo ufw allow 8086
	
	echo "Creating the admin user"
	#influx
	#CREATE USER admin WITH PASSWORD 'adminpassword' WITH ALL PRIVILEGES
	#exit
	read -p "What is the IP Address of your RPi: " ipaddress
	bash <(curl -sL "http://$ipaddress:8086/query" --data-urlencode "q=CREATE USER admin WITH PASSWORD 'adminpassword' WITH ALL PRIVILEGES")
	
	echo "Creating the database"
	#influx -username admin -password adminpassword
	#CREATE DATABASE zymatic
	bash <(curl -sL "http://$ipaddress:8086/query" --data-urlencode "q=CREATE DATABASE zymatic")
	
	#use zymatic
	echo "Creating the grafana user"
	#create user grafana with password 'changeme' with all privileges
	#grant all privileges on zymatic to grafana
	bash <(curl -sL "http://$ipaddress:8086/query" --data-urlencode "q=CREATE USER grafana WITH PASSWORD 'changeme'")
	bash <(curl -sL "http://$ipaddress:8086/query" --data-urlencode "q=GRANT ALL PRIVILEGES ON zymatic TO grafana")
	
	echo "Creating the nodered user"
	#create user nodered with password 'changeme' with all privileges
	#grant all privileges on zymatic to node-red
	bash <(curl -sL "http://$ipaddress:8086/query" --data-urlencode "q=CREATE USER nodered WITH PASSWORD 'changeme'")
	bash <(curl -sL "http://$ipaddress:8086/query" --data-urlencode "q=GRANT ALL PRIVILEGES ON zymatic TO nodered")
	#exit
	#bash <(curl -sL "http://localhost:8086/query" --data-urlencode "u=admin" --data-urlencode "p=adminpassword" --data-urlencode "q=SHOW DATABASES"
	
	DBCONFIG="/etc/influxdb/influxdb.conf"
	
	if grep -Fq "[http]" $DBCONFIG
	then
		# security file present...
		echo "Modifying security"
		
		#Enable HTTP
		grep -q 'Determines whether HTTP endpoint is enabled' /$DBCONFIG && sudo sed -i '/^### \[http\]/,/^### \[logging\]/{/^\(### \[http\]\|### \[logging\]\)$/b a;/^ *# *enabled.*$/s/#//; :a}' $DBCONFIG || sudo sed -i 's|^[http]|a enabled = true' $DBCONFIG
		sudo sed -i '/^### \[http\]/,/^### \[logging\]/{/^\(### \[http\]\|### \[logging\]\)$/b a;s/^ *enabled = false/  enabled = true/; :a}' $DBCONFIG
		
		#Enable authorization
		grep -q 'auth-enabled.*' /$DBCONFIG && sudo sed -i '/^### \[http\]/,/^### \[logging\]/{/^### \[\(http\|logging\)\]$/b a;/^ *# *auth-enabled.*$/s/#//; :a}' $DBCONFIG || sudo sed -i 's|^[http]|a auth-enabled = true' $DBCONFIG
		sudo sed -i 's|^ *auth-enabled = false|  auth-enabled = true|' $DBCONFIG
		
		grep -q 'pprof-enabled.*' /$DBCONFIG && sudo sed -i '/^### \[http\]/,/^### \[logging\]/{/^### \[\(http\|logging\)\]$/b a;/^ *# *pprof-enabled.*$/s/#//; :a}' $DBCONFIG || sudo sed -i 's|^[http]|a pprof-enabled = true' $DBCONFIG
		sudo sed -i 's|^ *pprof-enabled = false|  pprof-enabled = true|' $DBCONFIG
		
		grep -q 'pprof-auth-enabled.*' /$DBCONFIG && sudo sed -i '/^### \[http\]/,/^### \[logging\]/{/^### \[\(http\|logging\)\]$/b a;/^ *# *pprof-auth-enabled.*$/s/#//; :a}' $DBCONFIG || sudo sed -i 's|^[http]|a pprof-auth-enabled = true' $DBCONFIG
		sudo sed -i 's|^ *pprof-auth-enabled = false|  pprof-auth-enabled = true|' $DBCONFIG
		
		grep -q 'ping-auth-enabled.*' /$DBCONFIG && sudo sed -i '/^### \[http\]/,/^### \[logging\]/{/^### \[\(http\|logging\)\]$/b a;/^ *# *ping-auth-enabled.*$/s/#//; :a}' $DBCONFIG || sudo sed -i 's|^[http]|a ping-auth-enabled = true' $DBCONFIG
		sudo sed -i 's|^ *ping-auth-enabled = false|  ping-auth-enabled = true|' $DBCONFIG
	else
		# Create the definition
		echo "Creating security"
		echo "[http]" >> $DBCONFIG
		echo "auth-enabled = true" >> $DBCONFIG
		echo "pprof-enabled = true" >> $DBCONFIG
		echo "pprof-auth-enabled = true" >> $DBCONFIG
		echo "ping-auth-enabled = true" >> $DBCONFIG
	fi
	
	sudo systemctl restart influxdb

	echo "Checking for influxdb" 
	while ! pgrep -u influxdb influxd
		do
		sleep 1s 
	done
	echo "InfluxDB started"
else
	echo ""
	echo "Skipping influxdb installation"
fi

#install grafana
#******************************************************************************
#Grafana admin password = admnin, set to changeme
read -n 1 -s -r -p "Do you want to install grafana? [y/n]: " userinput
if [ "$userinput" = "y" ]
then 
	echo ""
	echo "Installing grafana"
	read -n 1 -s -r -p "Are you installing on a RPi A, B or Zero? [y/n]: " userinput
	if [ "$userinput" = "y" ]
	then 
		#Raspberry Pi A/B/Zero
		echo ""
		echo "Installing the Grafana service on RPi A/B/Zero"
		sudo apt install -y adduser libfontconfig1
		wget https://dl.grafana.com/oss/release/grafana-rpi_7.5.4_armhf.deb
		sudo dpkg -i grafana-rpi_7.5.4_armhf.deb
	else
		#Raspberry Pi 3 and up
		echo ""
		echo "Installing the Grafana service on RPi 3 and up"
		wget -q -O - https://packages.grafana.com/gpg.key | sudo apt-key add -
		echo "deb https://packages.grafana.com/oss/deb stable main" | sudo tee -a /etc/apt/sources.list.d/grafana.list

		sudo apt update
		sudo apt install grafana
	fi

	sudo systemctl daemon-reload
	sudo systemctl enable grafana-server
	sudo systemctl start grafana-server
else
	echo ""
	echo "Skipping grafana installation"
fi

#copy and rename node-red flow
#******************************************************************************
read -n 1 -s -r -p "Do you want to install the node-red flow? [y/n]: " userinput
if [ "$userinput" = "y" ]
then
	echo ""
	echo "Installing node-red flow"
	read -p "What is the Hostname of your RPi: " hostname
	NODEREDFLOW="flows_$hostname.json"
	
	#Download and copy node-red flow to /home/pi/.node-red
	echo "Retrieving Node-Red Flow" 
	wget -L https://raw.githubusercontent.com/sctn4elk/Test-Repo/main/Zymatic_v2.5_4.12.2021.json -P /home/pi
	if [ -f "/home/pi/$FLOW" ]
	then
		cp /home/pi/$FLOW /home/pi/.node-red/$NODEREDFLOW
	else
		echo "ZYMATIC NODE-RED FLOW ($FLOW) does not exist in /home/pi"
	fi
	
	#make beerXML directory
	echo "Creating beerXML directory"
	mkdir -p /home/pi/Documents/beerXML
	
	#Download and copy test recipe to /home/pi/Documents/beerXML
	echo "Retrieving beerXML Test Recipe" 
	wget -L https://raw.githubusercontent.com/sctn4elk/Test-Repo/main/Zymatic_Test_Recipe.xml -P /home/pi
	if [ -f "/home/pi/$ZYMATICRECIPE" ]
	then
		cp /home/pi/$ZYMATICRECIPE /home/pi/Documents/beerXML/$ZYMATICRECIPE
	else
		echo "ZYMATIC NODE-RED TEST RECIPE ($ZYMATICRECIPE) does not exist in /home/pi"
	fi
else
	echo ""
	echo "Skipping node-red flow installation"
fi

#completing the installation
#******************************************************************************
echo "Completing the installation"
sudo apt update 
sudo apt full-upgrade
sudo apt autoremove
sudo apt clean

echo "Install complete, rebooting."
sudo reboot

