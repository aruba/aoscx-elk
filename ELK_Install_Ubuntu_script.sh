#!/bin/bash

###
### This script installs and configures the ELK stack on a default Ubuntu 
###  22.04/24.04 server install.
### The only specific prerequisite for running this script is OpenSSH.
###
### A static IP configuration is strongly recommended, with either single or 
###  dual network interfaces.
###
### This should be run as the non-root user account created during Ubuntu server 
### installation, and utilizes sudo during the deployment process.
###
### Based on the original script hosted at: https://github.com/tdmakepeace/ELK_Single_script 
###
### To start this script from an Ubuntu server instance, run the following 
###  command:
###
### wget -O ELK_Install_Ubuntu_script.sh https://raw.githubusercontent.com/aruba/aoscx-elk/refs/heads/aoscx_10.15/ELK_Install_Ubuntu_script.sh && chmod +x ELK_Install_Ubuntu_script.sh && ./ELK_Install_Ubuntu_script.sh
###
### Copyright 2025 Hewlett Packard Enterprise Development LP.
###
###	Licensed under the Apache License, Version 2.0 (the "License");
### you may not use this file except in compliance with the License.
### You may obtain a copy of the License at
### 
###     http://www.apache.org/licenses/LICENSE-2.0
### 
### Unless required by applicable law or agreed to in writing, software
### distributed under the License is distributed on an "AS IS" BASIS,
### WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
### See the License for the specific language governing permissions and
### limitations under the License.

ELK="TAG=8.16.1"

	
rebootserver()
{
	echo -e "Rebooting the system...\n"
	
	sleep 5
	sudo reboot
}

updates()
{	
	sudo apt-get update 
	sudo NEEDRESTART_SUSPEND=1 apt-get dist-upgrade --yes 

	sleep 10
}

basenote()
{
	## Update all the base image of Ubuntu before we progress. 
	## then installs all the dependencies and sets up the permissions for Docker
	##clear
	echo -e "\nThis script will run unattended for several minutes to perform base setup of the server environment in preparation for Elastic stack deployment. It might appear to have paused, but leave it running until the system reboots.

A static IP configuration is strongly recommended.

Press Ctrl+C to exit if you need to configure a static IP address, then run this script again.\n" | fold -w 80 -s
	read -p "Press enter to continue..."
	}

elknote()
{
	## Update all the base image of Ubuntu before we progress. 
	
	echo -e "\nThis workflow requires input to select the desired application version, optionally configure an ElastiFlow license key, and will then run unattended to deploy and configure the ELK Stack components.\n" | fold -w 80 -s
	echo -e "Please do not interrupt the script during this process, to avoid leaving the application in a partially-deployed state.\n" | fold -w 80 -s
	read -p "Press enter to continue..."
	
}

dockerupnote()
{
	echo -e "\nAccess the ELK Stack application in a browser from the following URL: 
				
	'http://$localip:5601'
				
If the server is rebooted, allow 5 minutes for all services to start before you attempt to access the Kibana dashboards.\n" | fold -w 80 -s
		read -p "Services setup. Press enter to continue..."
}

base()
{
	real_user=$(whoami)

	updates
	
	cd /
	sudo mkdir cxtools
	sudo chown $real_user:$real_user cxtools
	sudo chmod 777 cxtools
	mkdir -p /cxtools/
	mkdir -p /cxtools/scripts
	sudo mkdir -p /etc/apt/keyrings

	sudo NEEDRESTART_SUSPEND=1 apt-get install curl gnupg ca-certificates lsb-release --yes 
	sudo mkdir -p /etc/apt/keyrings
	curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg  
	
	sudo echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
	sudo apt-get update --allow-insecure-repositories
	sudo NEEDRESTART_SUSPEND=1 apt-get dist-upgrade --yes 
	
	version=` more /etc/os-release |grep VERSION_ID | cut -d \" -f 2`
	if  [[ "$version" == "24.04" ]]; then
# Ubuntu 24.04
		sudo NEEDRESTART_SUSPEND=1 apt-get install unzip docker-ce docker-ce-cli containerd.io docker-compose-plugin python3.12-venv tmux python3-pip python3-venv --yes 
	elif [[ "$version" == "22.04" ]]; then
# Ubuntu 22.04
		sudo NEEDRESTART_SUSPEND=1 apt-get install unzip docker-ce docker-ce-cli containerd.io docker-compose-plugin python3.11-venv tmux python3-pip python3-venv --yes 
	elif [[ "$version" == "20.04" ]]; then
# Ubuntu 20.04
		sudo NEEDRESTART_SUSPEND=1 apt-get install unzip docker-ce docker-ce-cli containerd.io docker-compose-plugin python3.9-venv tmux python3-pip python3-venv --yes 
	else
		sudo NEEDRESTART_SUSPEND=1 apt-get install unzip docker-ce docker-ce-cli containerd.io docker-compose-plugin python3.8-venv tmux python3-pip python3-venv --yes 
	fi

	sudo usermod -aG docker $real_user
}




elk()
{
	cd /cxtools/

	git clone https://github.com/aruba/aoscx-elk.git 

	cd /cxtools/aoscx-elk

	`git branch --all | cut -d "/" -f3 > /cxtools/gitversion.txt`
	echo -e "Enter a line number to select a branch:\n"
	git branch --all | cut -d "/" -f3 | grep -n ''
	read x
	elkver=`sed "$x,1!d" /cxtools/gitversion.txt`
	git checkout $elkver

	cp docker-compose.yml docker-compose.yml.orig
	sed -i.bak  's/EF_OUTPUT_ELASTICSEARCH_ENABLE: '\''false'\''/EF_OUTPUT_ELASTICSEARCH_ENABLE: '\''true'\''/' docker-compose.yml
	localip=`hostname -I | cut -d " " -f1`

	sed -i.bak -r "s/EF_OUTPUT_ELASTICSEARCH_ADDRESSES: 'CHANGEME:9200'/EF_OUTPUT_ELASTICSEARCH_ADDRESSES: '$localip:9200'/" docker-compose.yml
	sed -i.bak -r "s/#EF_OUTPUT_ELASTICSEARCH_INDEX_PERIOD: 'daily'/EF_OUTPUT_ELASTICSEARCH_INDEX_PERIOD: 'daily'/" docker-compose.yml

	read -p "Do you want to install a ElastiFlow license? [y/n]: " x

	x=${x,,}
	
	if  [ "$x" == "y" ]; then
			echo -e "Enter the account ID:\n"
			read a
			echo -e "Enter the license key:\n"
			read b
			
		
		sed -i.bak -r "s/#EF_ACCOUNT_ID: ''/EF_ACCOUNT_ID: '$a'/" docker-compose.yml
		sed -i.bak -r "s/#EF_FLOW_LICENSE_KEY: ''/EF_FLOW_LICENSE_KEY: '$b'/" docker-compose.yml
		

	else
		echo "Continuing..."
	fi
		
	echo -e "\nHere are changes made to the docker-compose.yml file:

Before:

EF_OUTPUT_ELASTICSEARCH_ENABLE: 'false'
EF_OUTPUT_ELASTICSEARCH_ADDRESSES: 'CHANGEME:9200'

After:\n"
	more docker-compose.yml |egrep -i 'EF_OUTPUT_ELASTICSEARCH_ENABLE|EF_OUTPUT_ELASTICSEARCH_ADDRESSES|EF_ACCOUNT_ID|EF_FLOW_LICENSE_KEY'
	read -p "Press enter to continue..."
	
	echo -e "\nStarting ELK installation and setup. This will take a while...\n"					
	cd /cxtools/aoscx-elk/
	echo $ELK >.env
	mkdir -p data/es_backups
	mkdir -p data/cx_es
	mkdir -p data/elastiflow
	chmod -R 777 ./data
	sudo sysctl -w vm.max_map_count=262144
	echo vm.max_map_count=262144 | sudo tee -a /etc/sysctl.conf 
}

dockerup()
{		
	cd /cxtools/aoscx-elk/
	echo -e "Setup in progress, please wait... (5%)\n"
				
	sleep 10 
			
	docker compose up --detach
	
	echo -e "Setup in progress, please wait... (15%)\n"

	echo -e "Waiting 100 seconds for services to start before configuration import...\n" | fold -w 80 -s
	sleep 20
	echo -e "80 seconds remaining...\n"
	sleep 20
	echo -e "60 seconds remaining...\n"
	sleep 20
	echo -e "40 seconds remaining...\n"
	sleep 20
	echo -e "20 seconds remaining...\n"
	sleep 15
	echo -e "5 seconds remaining...\n"
	sleep 1
	echo -e "4 seconds remaining...\n"
	sleep 1
	echo -e "3 seconds remaining...\n"
	sleep 1
	echo -e "2 seconds remaining...\n"
	sleep 1
	echo -e "1 second remaining...\n"
	sleep 1

	echo -e "Deploying collector configuration...\n"

	curl --silent --output /dev/null --show-error --fail --noproxy '*' -XPUT -H'Content-Type: application/json' 'http://localhost:9200/_index_template/cx10000-fwlog?pretty' -d @./elasticsearch/cx10k_fwlog_mapping.json
	curl --silent --output /dev/null --show-error --fail --noproxy '*' -XPUT -H'Content-Type: application/json' 'http://localhost:9200/_snapshot/my_fs_backup' -d @./elasticsearch/cx10k_fs.json
	curl --silent --output /dev/null --show-error --fail --noproxy '*' -XPUT -H'Content-Type: application/json' 'http://localhost:9200/_slm/policy/cx10000' -d @./elasticsearch/cx10k_slm.json
	curl --silent --output /dev/null --show-error --fail --noproxy '*' -XPUT -H'Content-Type: application/json' 'http://localhost:9200/_ilm/policy/cx10000' -d @./elasticsearch/cx10k_ilm.json
	curl --silent --output /dev/null --show-error --fail --noproxy '*' -XPUT -H'Content-Type: application/json' 'http://localhost:9200/_slm/policy/elastiflow' -d @./elasticsearch/elastiflow_slm.json
	curl --silent --output /dev/null --show-error --fail --noproxy '*' -XPUT -H'Content-Type: application/json' 'http://localhost:9200/_ilm/policy/elastiflow' -d @./elasticsearch/elastiflow_ilm.json
	
	echo -e "Setup in progress, please wait... (70%)\n"
						
	sleep 10
	
	echo -e "Deploying dashboard configuration...\n"

	cx10kdash=`ls -t ./kibana/cx10k* | head -1`
	elastiflowdash=`ls -t  ./kibana/kib* | head -1`
	curl --silent --output /dev/null --show-error --fail --noproxy '*' -X POST "http://localhost:5601/api/saved_objects/_import?overwrite=true" -H "kbn-xsrf: true" -H "securitytenant: global" --form file=@$cx10kdash
	curl --silent --output /dev/null --show-error --fail --noproxy '*' -X POST "http://localhost:5601/api/saved_objects/_import?overwrite=true" -H "kbn-xsrf: true" -H "securitytenant: global" --form file=@$elastiflowdash
	
	echo -e "Setup in progress, please wait... (80%)\n"

	sleep 20	
}

proxy()
{
	echo -e "\nSelect the type of proxy server:\n" | fold -w 80 -s
	read -p "[A]uthenticated, [N]on-authenticated, or anything else to return to main menu: " p

	p=${p,,}

  	if  [[ "$p" == "a" ]]; then
  	 	echo -e "Enter the proxy server IPv4 address or fully-qualified domain name.
 
Example: 

192.168.0.250 
or
yourproxyaddress.co.uk\n" | fold -w 80 -s
		read url
		
		read -p "Proxy server listening port: " port
		read -p "Proxy server username: " user
		read -p "Proxy server password: " pass
		
		### Needed for NO_PROXY environment variable
		noproxylocalip=`hostname -I | cut -d " " -f1`

		sudo rm -f -- /etc/apt/apt.conf
		sudo touch /etc/apt/apt.conf
		sudo chmod 777 /etc/apt/apt.conf
		echo "Acquire::http::Proxy \"http://$user:$pass@$url:$port\";" >>  /etc/apt/apt.conf
		
		git config --global http.proxy http://$user:$pass@p$url:$port

		### docker
		sudo mkdir -p /etc/systemd/system/docker.service.d
		sudo rm -f -- /etc/systemd/system/docker.service.d/proxy.conf
		sudo touch /etc/systemd/system/docker.service.d/proxy.conf
		sudo chmod 777 /etc/systemd/system/docker.service.d/proxy.conf
		echo "[Service]
		EnvironmentFile=/etc/system/default/docker
" >> /etc/systemd/system/docker.service.d/proxy.conf
		sudo mkdir -p /etc/system/default/
		sudo chmod 777 /etc/system/default/
		sudo rm -f -- /etc/system/default/docker
		sudo touch /etc/system/default/docker
		sudo chmod 777 /etc/system/default/docker
		echo "HTTP_PROXY='http%3A%2F%2F$user%3A$pass%40$url%3A$port%2F'
NO_PROXY=localhost,127.0.0.1,$noproxylocalip,::1
" >/etc/system/default/docker

#  		sudo systemctl daemon-reload
#  		sudo systemctl restart docker.service

		echo -e "Proxy server configuration complete, returning to main menu...\n"
	
	elif  [ "$p" == "n" ]; then
  	 	echo -e "Enter the proxy server IPv4 address or fully-qualified domain name.
 
Example: 

192.168.0.250 
or
yourproxyaddress.co.uk\n" | fold -w 80 -s

		read url
		
		read -p "Proxy server listening port: " port
		
		### cURL
		touch ~/.curlrc
		echo "proxy = $url:$port" >> ~/.curlrc

		sudo rm -f -- /etc/apt/apt.conf
		sudo touch /etc/apt/apt.conf
		sudo chmod 777 /etc/apt/apt.conf
		echo "Acquire::http::Proxy \"http://$url:$port\";" >> /etc/apt/apt.conf
		git config --global http.proxy http://$url:$port

		### docker
		sudo mkdir -p /etc/systemd/system/docker.service.d
		sudo rm -f -- /etc/systemd/system/docker.service.d/proxy.conf
		sudo touch /etc/systemd/system/docker.service.d/proxy.conf
		sudo chmod 777 /etc/systemd/system/docker.service.d/proxy.conf
		echo "[Service]
Environment=\"HTTP_PROXY=http://$url:$port\"
Environment=\"HTTPS_PROXY=http://$url:$port\"
Environment=\"NO_PROXY=localhost,127.0.0.1,$noproxylocalip,::1\"
" >> /etc/systemd/system/docker.service.d/proxy.conf
#  		sudo systemctl daemon-reload
#  		sudo systemctl restart docker.service

		echo -e "Proxy server configuration complete, returning to main menu...\n"

	else 
		echo "Returning to main menu..."
	fi
		
		
}

upgrade()
{
	cd /cxtools/aoscx-elk/
		
	docker compose down
	updates
	echo $ELK >.env
	
	cd /cxtools/aoscx-elk
	##clear 
	git branch --all | cut -d "/" -f3 > gitversion.txt
	echo -e "Enter a line number to select a branch to upgrade to:\n"
	git branch --all | cut -d "/" -f3 |grep -n ''
	read x
	orig=`sed "1,1!d" gitversion.txt|cut -d ' ' -f 2`
	elkver=`sed "$x,1!d" gitversion.txt`
	##echo $elkver
	sudo cp docker-compose.yml docker-compose.yml.$orig
	git checkout  $elkver --force
	git pull
	localip=`hostname -I | cut -d " " -f1`
	
	olddocker=`ls -t docker*aos* |head -1`
	
	
	EFaccount=`more $olddocker |grep EF_ACCOUNT_ID| cut -d ":" -f 2|cut -d " " -f2  `
	EFLice=`more $olddocker |grep EF_FLOW_LICENSE_KEY| cut -d ":" -f 2|cut -d " " -f2  `
	sed -i.bak  's/EF_OUTPUT_ELASTICSEARCH_ENABLE: '\''false'\''/EF_OUTPUT_ELASTICSEARCH_ENABLE: '\''true'\''/' docker-compose.yml
	sed -i.bak -r "s/EF_OUTPUT_ELASTICSEARCH_ADDRESSES: 'CHANGEME:9200'/EF_OUTPUT_ELASTICSEARCH_ADDRESSES: '$localip:9200'/" docker-compose.yml
	sed -i.bak -r "s/#EF_ACCOUNT_ID: ''/EF_ACCOUNT_ID: $EFaccount/" docker-compose.yml
	sed -i.bak -r "s/#EF_FLOW_LICENSE_KEY: ''/EF_FLOW_LICENSE_KEY: $EFLice/" docker-compose.yml
	
	echo -e "The following changes have been made to the docker-compose.yml file:

Before:
	EF_OUTPUT_ELASTICSEARCH_ENABLE: 'false'
	EF_OUTPUT_ELASTICSEARCH_ADDRESSES: 'CHANGEME:9200'

After:
	EF_OUTPUT_ELASTICSEARCH_ENABLE: 'true'
	EF_OUTPUT_ELASTICSEARCH_ADDRESSES: '<YourIP>:9200'

Running version:
"
			
	more docker-compose.yml |egrep -i 'EF_OUTPUT_ELASTICSEARCH_ENABLE|EF_OUTPUT_ELASTICSEARCH_ADDRESSES|EF_ACCOUNT_ID|EF_FLOW_LICENSE_KEY'
	read -p "Press enter to continue"
	
	echo -e "\nStarting installation and setup, this will take a while...\n"
				
	cd /cxtools/aoscx-elk/
	echo $ELK >.env
	
	
}

while true ;
do
	##clear
  echo -e "\nPress Ctrl+C to exit at any time.\n"
  echo -e "This script is used to set up an instance of the ELK Stack for collection, monitoring, and analysis of flow records, firewall logs, and event logs generated by HPE Aruba Networking CX switches.

Workflows provided by this script will: 

- Prepare the base system for ELK Stack deployment by ensuring that the operating system is up to date and that all prerequisites are installed
- Deploy and configure the ELK Stack components using Docker container instances and provided configuration files 
- Update deployed ELK Stack components to the latest release

If this is your first time running this script on this system, select [B] to start the base system preparation workflow, which will end with a system reboot; once the system is up and running again, execute this script a second time from the local directory to continue with the deployment process.

NOTE: If a proxy server is required for this system to connect to the internet, select [P] to run the proxy server configuration workflow prior to starting base system preparation.

If base system preparation and reboot have been completed, select [E] to run the ELK Stack deployment workflow.

If the ELK Stack is already deployed and needs to be updated, select [U] to run the update workflow.\n" | fold -w 80 -s
	
	read -p "[B]ase system preparation, [E]LK Stack deployment, [U]pdate, [P]roxy configuration, or e[X]it: " x

	x=${x,,}

	if  [[ "$x" == "b" ]]; then
		echo -e "\nPress Ctrl+C to exit at any time.\n"
		echo -e "This workflow should only be run once; do not run it again unless you have previously cancelled it before completion.\n" | fold -w 80 -s
		read -p "Enter 'C' to continue: " x
		
		x=${x,,}

		while [[ "$x" ==  "c" ]];
		do
			basenote
			base 
			rebootserver
			x="done"
			exit 0
		done
	
	elif [[ "$x" == "e" ]]; then
		echo -e "\nPress Ctrl+C to exit at any time.\n"
		echo -e "This workflow should only be run once; running it additional times	will result in restoring the ELK Stack to default settings and removal of all stored data.\n" | fold -w 80 -s
		read -p "Enter 'C' to continue: " x
		x=${x,,}
		while [[ "$x" ==  "c" ]] ;
		do
			elknote
			elk 
			dockerup
			dockerupnote
			x="done"
			exit 0
		done
				
	elif [[ "$x" == "p" ]]; then
		echo -e "\nPress Ctrl+C to exit at any time.\n"
		echo -e "This workflow should normally only be run once; it should only	need to be run again if the ELK Stack components need to be updated or redeployed and the proxy server configuration has changed since the original deployment.\n" | fold -w 80 -s
		read -p "Enter 'C' to continue: " x
		x=${x,,}

			##clear
		while [  "$x" ==   "c" ] ;
		do
			proxy 
			x="done"
		done
				

	elif [[ "$x" ==  "u" ]]; then
		##clear
		echo -e "\nPress Ctrl+C to exit at any time.\n"
		echo -e "This workflow updates base system software packages and allows selection of an updated version of the ELK Stack environment from the GitHub repository.\n" | fold -w 80 -s
		read -p "Enter 'C' to continue: " x
		x=${x,,}

		while [  "$x" ==   "c" ] ;
		do
			upgrade
			dockerup
			dockerupnote
			rebootserver
			x="done"
		done
				

	elif [[ "$x" ==  "x" ]]; then
		echo -e "\nExiting...\n"
		exit 0

	else
		echo -e "\nInvalid option, try again...\n"
	fi

done   
