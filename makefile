# -----------------------------------------------------------------
#
#    NAME
#      Dynamicscaling Telegraf InfluxDB Grafana (ODyS-TIG)
#
#    DESCRIPTION
#      ODyS-TIG makefile
#
#    AUTHOR:
#      ruggero.citton@oracle.com 
#
#    NOTES
#
#    MODIFIED   (MM/DD/YY)
#    rcitton     12/02/25 - Upgrade to InfluxDB 2.x
#    rcitton     03/05/24 - 
#    rcitton     12/19/23 - +tocpu
#    rcitton     11/06/23 - update
#    rcitton     03/16/23 - creation
#
# -----------------------------------------------------------------

###############################################################################
#  SET ENV VARIABLES                                                          #
###############################################################################
include ./config.env

# Determines if sed needs a backup extension (as required by MacOS/BSD sed)
ifeq ($(OS_TYPE),MacOS)
	SED_INPLACE_EXT = ''
else
	SED_INPLACE_EXT = 
endif

# Defines the project root path for volumes in the compose file. 
ifeq ($(OS_TYPE),MacOS)
# Check VM_MOUNT_ROOT
ifeq ($(or $(VM_MOUNT_ROOT),),)
$(error VM_MOUNT_ROOT is not set or empty on 'config.env' but required for MacOS)
endif

# Check MACOS_HOST_PROJECT_PATH
ifeq ($(or $(MACOS_HOST_PROJECT_PATH),),)
$(error MACOS_HOST_PROJECT_PATH is not set or empty on 'config.env' but required for MacOS)
endif

	COMPOSE_ROOT = $(VM_MOUNT_ROOT)
	HOST_PROJECT_PATH = $(MACOS_HOST_PROJECT_PATH)
else
	COMPOSE_ROOT = $(ROOTDIR)
	HOST_PROJECT_PATH = $(ROOTDIR)
endif

# Variable for the temporary file
DATASOURCE_TEMP_FILE = $(HOST_PROJECT_PATH)/grafana/provisioning/datasources/datasource.yml.tmp

# -----------------------------------------------------------------------------
SHELL=/bin/bash
ROOTDIR=$(PWD)
ODYSCHART_PATH="/opt/dynamicscaling-chart/dynamicscaling-chart.bin"
ODYSCHARTRPM_PATH=./odys_chart/dynamicscaling-chart-*.rpm


###########################
## Colors definition     ##
###########################
COLOUR_GREEN=\033[0;32m
COLOUR_RED=\033[0;31m
COLOUR_YELLOW=\033[0;33m
COLOUR_BLUE=\033[0;34m
COLOUR_END=\033[0m


###########################
## OS Commands           ##
###########################
IDU  := $(shell id -u)
IDG  := $(shell id -g)


###########################
## Help Setup            ##
###########################
.DEFAULT_GOAL := help
.PHONY: help
help:
	@echo -e "------------------------------------------------------------------" 
	@echo -e "$(COLOUR_GREEN)                   ODyS-TIG Commands$(COLOUR_END)" 
	@echo "------------------------------------------------------------------"
	@echo "        Command                    Action"
	@echo "------------------------------------------------------------------"
	@echo "🔧  make setup        ➜  Setup          ODyS-TIG"
	@echo "🔧  make setup_monc   ➜  Setup+Measure  ocpu,nload,cload"
	@echo "🔧  make setup_mop    ➜  Setup+Measure  ocpu,pload"
	@echo "------------------------------------------------------------------"
	@echo "🦭  make ct           ➜  Connect        Telegraf-container"
	@echo "🦭  make ci           ➜  Connect        Influxdb-container"
	@echo "🦭  make cg           ➜  Connect        Grafana-container"
	@echo "------------------------------------------------------------------"
	@echo "🚀  make start        ➜  Start          ODyS-TIG"
	@echo "🛑  make stop         ➜  Stop           ODyS-TIG"
	@echo "🔎  make status       ➜  Status         ODyS-TIG"
	@echo "------------------------------------------------------------------"
	@echo "📈  make monc         ➜  Measure        ocpu,nload,cload"
	@echo "📈  make mop          ➜  Measure        ocpu,pload"
	@echo "📈  make ocpu         ➜  Measure        ocpu"
	@echo "📈  make nload        ➜  Measure        nload"
	@echo "📈  make cload        ➜  Measure        cload"
	@echo "📈  make pload        ➜  Measure        pload"
	@echo "------------------------------------------------------------------"
	@echo "📜  make mextract     ➜  Extract"
	@echo "📜  make mtextract    ➜  Extract-Type"
	@echo "------------------------------------------------------------------"
	@echo "♻️   make reset_monc   ➜  Reset+Measure  ocpu,nload,cload"
	@echo "♻️   make reset_mop    ➜  Reset+Measure  ocpu,pload"
	@echo "------------------------------------------------------------------"
	@echo "🧹  make cleanup      ➜  Cleanup        ODyS-TIG_containers"
	@echo "🧹  make cleanupall   ➜  Cleanup        ODyS-TIG_containers&images"
	@echo "------------------------------------------------------------------"
	@echo

###############################################################################
#  Macro  SECTION                                                             #
###############################################################################

reset_monc: cleanup setup_monc ## ♻️ Reset+Measure ocpu,nload,cload
reset_mop: cleanup setup_mop ## ♻️ Reset+Measure ocpu,pload

setup_monc: setup monc ## ✅ Setup+Measure ocpu,nload,cload
setup_mop: setup mop ## ✅ Setup+Measure ocpu,pload

###############################################################################
#  MAIN CONTAINERS SECTION                                                    #
###############################################################################
setup: ## 🔧 Setup ODyS-TIG
	@echo -e "$(COLOUR_YELLOW)-------------------------$(COLOUR_END)"
	@echo -e "$(COLOUR_YELLOW)Making the ODyS-TIG...$(COLOUR_END)"
	@echo -e "$(COLOUR_YELLOW)-------------------------$(COLOUR_END)"
ifeq (,$(wildcard $(ODYSCHARTRPM_PATH)))
	@echo -e "$(COLOUR_RED)Missing dynamicscaling-chart.rpm$(COLOUR_END)"
	exit 1
endif

ifndef PROXY
	@echo -e "$(COLOUR_BLUE)...proxy not defined$(COLOUR_END)"
else
	@echo -e "$(COLOUR_BLUE)...setting proxy env variables$(COLOUR_END)"
	export HTTPS_PROXY=$(PROXY)
	export HTTP_PROXY=$(PROXY)
	export NO_PROXY="localhost,127.0.0.1,/var/run/docker.sock"
	export http_proxy=$(PROXY)
	export https_proxy=$(PROXY)
	export no_proxy="localhost,127.0.0.1,/var/run/docker.sock"
endif
	@echo
	@echo -e "$(COLOUR_BLUE)...making odys-chart container$(COLOUR_END)"
	$(CONTAINER_ENGINE) build -t odys-chart ./
	@echo
	@echo -e "$(COLOUR_BLUE)..making ODyS-TIG compose$(COLOUR_END)"
	@TIG_ROOT=$(COMPOSE_ROOT) $(CONTAINER_COMPOSE) -f compose.yml --env-file config.env up -d
	@sleep 10
	@echo
	@echo -e "$(COLOUR_BLUE)...setup grafana container$(COLOUR_END)"
	$(CONTAINER_ENGINE) stop odys-grafana
	@cp $(HOST_PROJECT_PATH)/grafana/provisioning/datasources/datasource.yml $(DATASOURCE_TEMP_FILE)
	@sed -i $(SED_INPLACE_EXT) 's|PLACEHOLDER_INFLUXDB_ORG|$(INFLUXDB_INIT_ORG)|g' $(DATASOURCE_TEMP_FILE)
	@sed -i $(SED_INPLACE_EXT) 's|PLACEHOLDER_INFLUXDB_TOKEN|"Token $(INFLUXDB_INIT_ADMIN_TOKEN)"|g' $(DATASOURCE_TEMP_FILE)
	@$(CONTAINER_ENGINE) cp $(DATASOURCE_TEMP_FILE) odys-grafana:/etc/grafana/provisioning/datasources/datasource.yml
	$(CONTAINER_ENGINE) start odys-grafana
	@sleep 5
	@echo -e "$(COLOUR_GREEN)---------------------------------------------------------$(COLOUR_END)"
	@echo -e "$(COLOUR_GREEN)ODyS-TIG is ready, please browse to http://localhost:3000$(COLOUR_END)"
	@echo -e "$(COLOUR_GREEN)---------------------------------------------------------$(COLOUR_END)"

cleanup: ## 🧹 Cleanup ODyS-TIG_containers
	@echo -e "$(COLOUR_YELLOW)-------------------------$(COLOUR_END)"
	@echo -e "$(COLOUR_YELLOW)Cleaning up ODyS-TIG...$(COLOUR_END)"
	@echo -e "$(COLOUR_YELLOW)-------------------------$(COLOUR_END)"
	@echo -e "$(COLOUR_BLUE)...stopping ODyS-TIG compose$(COLOUR_END)"
	@$(CONTAINER_COMPOSE) stop
	@echo
	@echo -e "$(COLOUR_BLUE)...removing ODyS-TIG compose$(COLOUR_END)"
ifneq (,$(findstring docker,$(CONTAINER_ENGINE)))
	-$(CONTAINER_COMPOSE) rm --force -v
else
	-$(CONTAINER_ENGINE) rm odys-grafana
	-$(CONTAINER_ENGINE) rm odys-telegraf
	-$(CONTAINER_ENGINE) rm odys-influxdb
endif
ifneq (,$(findstring podman,$(CONTAINER_ENGINE)))
	@echo
	@echo -e "$(COLOUR_BLUE)...removing volumes & network$(COLOUR_END)"
	-$(CONTAINER_ENGINE) volume ls -qf dangling=true | xargs -r $(CONTAINER_ENGINE) volume rm
	-$(CONTAINER_ENGINE) network rm $$($(CONTAINER_ENGINE) network ls --filter=name='odys*' -q)
endif
	@echo
	@echo -e "$(COLOUR_BLUE)...removing csv entries$(COLOUR_END)"
	@-rm -f ./odys_csv/odys_csv_new/*
	@-rm -f ./odys_csv/odys_csv_old/*
	@-rm -f ./odys_csv/odys_csv_err/*
	@echo
	@echo -e "$(COLOUR_BLUE)...removing dashboards entries$(COLOUR_END)"
	@-rm -f ./grafana/provisioning/dashboards/ODyS-TIG\ -\ MONC_*.json
	@-rm -f ./grafana/provisioning/dashboards/ODyS-TIG\ -\ MOP_*.json
	@echo
	@echo -e "$(COLOUR_BLUE)...removing telegraf log$(COLOUR_END)"
	@-rm -f ./telegraf/log/*
	@echo -e "$(COLOUR_GREEN)-------------------------$(COLOUR_END)"
	@echo -e "$(COLOUR_GREEN)ODyS-TIG cleanup done!$(COLOUR_END)"
	@echo -e "$(COLOUR_GREEN)-------------------------$(COLOUR_END)"
	
cleanupall: ## 🧹 Cleanup ODyS-TIG_containers&images
	@echo -e "$(COLOUR_YELLOW)-------------------------$(COLOUR_END)"
	@echo -e "$(COLOUR_YELLOW)Cleaning up ODyS-TIG...$(COLOUR_END)"
	@echo -e "$(COLOUR_YELLOW)-------------------------$(COLOUR_END)"
	@echo -e "$(COLOUR_BLUE)...removing odys-chart container$(COLOUR_END)"
	-$(CONTAINER_ENGINE) rmi odys-chart
	@echo
	@echo -e "$(COLOUR_BLUE)...stopping ODyS-TIG compose$(COLOUR_END)"
	$(CONTAINER_COMPOSE) stop
	@echo
	@echo -e "$(COLOUR_BLUE)...removing ODyS-TIG compose$(COLOUR_END)"
ifneq (,$(findstring docker,$(CONTAINER_ENGINE)))
	-$(CONTAINER_COMPOSE) rm --force -v
else
	-$(CONTAINER_ENGINE) rm odys-grafana
	-$(CONTAINER_ENGINE) rm odys-telegraf
	-$(CONTAINER_ENGINE) rm odys-influxdb
endif
ifneq (,$(findstring podman,$(CONTAINER_ENGINE)))
	@echo
	@echo -e "$(COLOUR_BLUE)...removing volumes & network$(COLOUR_END)"
	-$(CONTAINER_ENGINE) volume ls -qf dangling=true | xargs -r $(CONTAINER_ENGINE) volume rm
	-$(CONTAINER_ENGINE) network rm $$($(CONTAINER_ENGINE) network ls --filter=name='odys*' -q)
endif
	@echo
	@echo -e "$(COLOUR_BLUE)...removing tig images$(COLOUR_END)"
ifneq (,$(findstring podman,$(CONTAINER_ENGINE)))
	-$(CONTAINER_ENGINE) rmi container-registry.oracle.com/os/oraclelinux:8-slim  docker.io/library/telegraf docker.io/library/influxdb:2.7 docker.io/grafana/grafana --force
else
	-$(CONTAINER_ENGINE) rmi oraclelinux:8-slim telegraf influxdb:2.7 grafana/grafana --force
endif
	@echo
	@echo -e "$(COLOUR_BLUE)...removing csv entries$(COLOUR_END)"
	@-rm -f ./odys_csv/odys_csv_new/*
	@-rm -f ./odys_csv/odys_csv_old/*
	@-rm -f ./odys_csv/odys_csv_err/*
	@echo
	@echo -e "$(COLOUR_BLUE)...removing dashboards entries$(COLOUR_END)"
	@-rm -f ./grafana/provisioning/dashboards/ODyS-TIG\ -\ MONC_*.json
	@-rm -f ./grafana/provisioning/dashboards/ODyS-TIG\ -\ MOP_*.json
	@echo
	@echo -e "$(COLOUR_BLUE)...removing telegraf log$(COLOUR_END)"
	@-rm -f ./telegraf/log/*
	@echo -e "$(COLOUR_GREEN)-------------------------$(COLOUR_END)"
	@echo -e "$(COLOUR_GREEN)ODyS-TIG cleanup done!$(COLOUR_END)"
	@echo -e "$(COLOUR_GREEN)-------------------------$(COLOUR_END)"

start: ## 🚀 Start ODyS-TIG
	@echo -e "$(COLOUR_YELLOW)-------------------------$(COLOUR_END)"
	@echo -e "$(COLOUR_YELLOW)Start up ODyS-TIG...$(COLOUR_END)"
	@echo -e "$(COLOUR_YELLOW)-------------------------$(COLOUR_END)"
	@$(CONTAINER_COMPOSE) start
	@echo -e "$(COLOUR_GREEN)---------------------------------------------------------$(COLOUR_END)"
	@echo -e "$(COLOUR_GREEN)ODyS-TIG is ready, please browse to http://localhost:3000$(COLOUR_END)"
	@echo -e "$(COLOUR_GREEN)---------------------------------------------------------$(COLOUR_END)"

stop: ## 🛑 Stop ODyS-TIG
	@echo -e "$(COLOUR_YELLOW)-------------------------$(COLOUR_END)"
	@echo -e "$(COLOUR_YELLOW)Stopping ODyS-TIG...$(COLOUR_END)"
	@echo -e "$(COLOUR_YELLOW)-------------------------$(COLOUR_END)"
	@$(CONTAINER_COMPOSE) stop

status: ## 🔎 Status ODyS-TIG
	@echo -e "$(COLOUR_YELLOW)-----------------------------$(COLOUR_END)"
	@echo -e "$(COLOUR_YELLOW)Show ODyS-TIG setup status...$(COLOUR_END)"
	@echo -e "$(COLOUR_YELLOW)-----------------------------$(COLOUR_END)"
	@echo -e "$(COLOUR_BLUE)ODyS-TIG containers--->$(COLOUR_END)"
	@$(CONTAINER_ENGINE) container ls --filter "name=odys*"
	@echo
	@echo
	@echo -e "$(COLOUR_BLUE)ODyS-TIG images--->$(COLOUR_END)"
	@$(CONTAINER_ENGINE) images --filter reference="*telegraf" --filter reference="*influxdb" --filter reference="*grafana/grafana" --filter reference="*odys-chart"

ct: ## 🖧 Connect Telegraf-container
	@echo -e "$(COLOUR_YELLOW)Connecting telegraf...$(COLOUR_END)"
	@$(CONTAINER_ENGINE) exec -it odys-telegraf bash

ci: ## 🖧 Connect Influxdb-container
	@echo -e "$(COLOUR_YELLOW)Connecting influxdb...$(COLOUR_END)"
	@$(CONTAINER_ENGINE) exec -it odys-influxdb bash

cg: ## 🖧 Connect Grafana-container
	@echo -e "$(COLOUR_YELLOW)Connecting grafana...$(COLOUR_END)"
	@$(CONTAINER_ENGINE) exec -it odys-grafana bash

###############################################################################
# ODyS Chart SECTION                                                          #
###############################################################################

monc: ocpu nload cload ## 📈 Measure ocpu,nload,cload
	@echo -e "$(COLOUR_GREEN)---------------------------------------------------------$(COLOUR_END)"
	@echo -e "$(COLOUR_GREEN)ODyS-TIG measure ready!$(COLOUR_END)"
	@echo -e "$(COLOUR_GREEN)---------------------------------------------------------$(COLOUR_END)"

mop: ocpu pload ## 📈 Measure ocpu,pload
	@echo -e "$(COLOUR_GREEN)---------------------------------------------------------$(COLOUR_END)"
	@echo -e "$(COLOUR_GREEN)ODyS-TIG measure ready!$(COLOUR_END)"
	@echo -e "$(COLOUR_GREEN)---------------------------------------------------------$(COLOUR_END)"

ocpu: ## 📈 Measure ocpu
	@echo -e "$(COLOUR_YELLOW)-------------------------$(COLOUR_END)"
	@echo -e "$(COLOUR_YELLOW)Extracting OCPU data...$(COLOUR_END)"
	@echo -e "$(COLOUR_YELLOW)-------------------------$(COLOUR_END)"
	$(CONTAINER_ENGINE) run --rm \
    -v "$(ROOTDIR)/odys_logs:/odys_logs:z" \
    -v "$(ROOTDIR)/odys_csv:/odys_csv:z" \
    --name odys-chart \
    odys-chart \
    $(ODYSCHART_PATH) \
        --cocpu \
        --csv \
        --nochart \
        --log ./odys_logs/dynamicscaling.log \
        --out ./odys_csv/odys_csv_new
	@chmod 666 ./odys_csv/odys_csv_new/*

nload: ## 📈 Measure nload
	@echo -e "$(COLOUR_YELLOW)-------------------------$(COLOUR_END)"
	@echo -e "$(COLOUR_YELLOW)Extracting Node Load data...$(COLOUR_END)"
	@echo -e "$(COLOUR_YELLOW)-------------------------$(COLOUR_END)"
	$(CONTAINER_ENGINE) run --rm \
    -v "$(ROOTDIR)/odys_logs:/odys_logs:z" \
    -v "$(ROOTDIR)/odys_csv:/odys_csv:z" \
    --name odys-chart \
    odys-chart \
    $(ODYSCHART_PATH) \
        --nload \
        --csv --nochart \
        --log ./odys_logs/dynamicscaling.log \
        --out ./odys_csv/odys_csv_new
	@chmod 666 ./odys_csv/odys_csv_new/*

cload: ## 📈 Measure cload
	@echo -e "$(COLOUR_YELLOW)-------------------------$(COLOUR_END)"
	@echo -e "$(COLOUR_YELLOW)Extracting Cluster Load data...$(COLOUR_END)"
	@echo -e "$(COLOUR_YELLOW)-------------------------$(COLOUR_END)"
	$(CONTAINER_ENGINE) run --rm \
    -v "$(ROOTDIR)/odys_logs:/odys_logs:z" \
    -v "$(ROOTDIR)/odys_csv:/odys_csv:z" \
    --name odys-chart \
    odys-chart \
    $(ODYSCHART_PATH) \
        --cload \
        --csv --nochart \
        --log ./odys_logs/dynamicscaling.log \
        --out ./odys_csv/odys_csv_new
	@chmod 666 ./odys_csv/odys_csv_new/*

pload: ## 📈 Measure pload
	@echo -e "$(COLOUR_YELLOW)-------------------------$(COLOUR_END)"
	@echo -e "$(COLOUR_YELLOW)Extracting Plugin Load data...$(COLOUR_END)"
	@echo -e "$(COLOUR_YELLOW)-------------------------$(COLOUR_END)"
	$(CONTAINER_ENGINE) run --rm \
    -v "$(ROOTDIR)/odys_logs:/odys_logs:z" \
    -v "$(ROOTDIR)/odys_csv:/odys_csv:z" \
    --name odys-chart \
    odys-chart \
    $(ODYSCHART_PATH) \
        --pload \
        --csv --nochart \
        --log ./odys_logs/dynamicscaling.log \
        --out ./odys_csv/odys_csv_new
	@chmod 666 ./odys_csv/odys_csv_new/*

mextract: ## 📜 Extract 
ifndef TYPE
	@echo -e "$(COLOUR_RED)ERROR:$(COLOUR_END) TYPE= is undefined, must be 'cocpu' or 'cload' or 'pload' or 'nload', exiting..."
	exit 1
endif

ifneq ($(TYPE),cocpu)
  ifneq ($(TYPE),cload)
    ifneq ($(TYPE),pload)
      ifneq ($(TYPE),nload)
			@echo -e "$(COLOUR_RED)ERROR:$(COLOUR_END) TYPE= is not valid, must be 'cocpu' or 'cload' or 'pload' or 'nload', exiting..."
			exit 1
       endif
     endif
   endif
endif

ifndef LABEL
	@echo -e "$(COLOUR_RED)ERROR:$(COLOUR_END) LABEL= is undefined, exiting..."
	exit 1
endif

	@echo
	@echo -e "$(COLOUR_YELLOW)-------------------------$(COLOUR_END)"
	@echo -e "$(COLOUR_YELLOW)Extracting $(TYPE) data...$(COLOUR_END)"
	@echo -e "$(COLOUR_YELLOW)-------------------------$(COLOUR_END)"
	$(CONTAINER_ENGINE) run --rm \
    -v "$(ROOTDIR)/odys_logs:/odys_logs:z" \
    -v "$(ROOTDIR)/odys_csv:/odys_csv:z" \
    --name odys-chart \
    odys-chart \
    $(ODYSCHART_PATH) \
        --$(TYPE) \
        --csv --nochart \
        --log ./odys_logs/$(LOG) \
        --out ./odys_csv/odys_csv_new \
        --label $(TYPE)_$(LABEL)
	@chmod 666 ./odys_csv/odys_csv_new/*

	@echo

ifneq ($(TYPE),pload)
	@echo -e "$(COLOUR_YELLOW)-------------------------$(COLOUR_END)"
	@echo -e "$(COLOUR_YELLOW)Setting-Up 'ODyS-TIG - MONC_$(LABEL).json' Grafana Dashboard...$(COLOUR_END)"
	@echo -e "$(COLOUR_YELLOW)-------------------------$(COLOUR_END)"
	@cp 'grafana/provisioning/dashboards/ODyS-TIG - MONC.json' 'grafana/provisioning/dashboards/ODyS-TIG - MONC_$(LABEL).json'
	@sed -i s/dynamicscaling-chart_ocpu.csv/dynamicscaling-chart_cocpu_$(LABEL).csv/g 'grafana/provisioning/dashboards/ODyS-TIG - MONC_$(LABEL).json'
	@sed -i s/dynamicscaling-chart_nload.csv/dynamicscaling-chart_nload_$(LABEL).csv/g 'grafana/provisioning/dashboards/ODyS-TIG - MONC_$(LABEL).json'
	@sed -i s/dynamicscaling-chart_cload.csv/dynamicscaling-chart_cload_$(LABEL).csv/g 'grafana/provisioning/dashboards/ODyS-TIG - MONC_$(LABEL).json'
	@sed -i s/'ODyS-TIG - MONC'/'ODyS-TIG - MONC - $(LABEL)'/g 'grafana/provisioning/dashboards/ODyS-TIG - MONC_$(LABEL).json'
endif

ifeq ($(TYPE),pload)
	@echo -e "$(COLOUR_YELLOW)-------------------------$(COLOUR_END)"
	@echo -e "$(COLOUR_YELLOW)Setting-Up 'ODyS-TIG - MOP_$(LABEL).json' Grafana Dashboard...$(COLOUR_END)"
	@echo -e "$(COLOUR_YELLOW)-------------------------$(COLOUR_END)"
	@cp 'grafana/provisioning/dashboards/ODyS-TIG - MOP.json' 'grafana/provisioning/dashboards/ODyS-TIG - MOP_$(LABEL).json'
	@sed -i s/dynamicscaling-chart_ocpu.csv/dynamicscaling-chart_cocpu_$(LABEL).csv/g 'grafana/provisioning/dashboards/ODyS-TIG - MOP_$(LABEL).json'
	@sed -i s/dynamicscaling-chart_pload.csv/dynamicscaling-chart_pload_$(LABEL).csv/g 'grafana/provisioning/dashboards/ODyS-TIG - MOP_$(LABEL).json'
	@sed -i s/'ODyS-TIG - MOP'/'ODyS-TIG - MOP - $(LABEL)'/g 'grafana/provisioning/dashboards/ODyS-TIG - MOP_$(LABEL).json'
endif

	@echo

ifneq ($(TYPE),pload)
	@echo -e "$(COLOUR_YELLOW)-------------------------$(COLOUR_END)"
	@echo -e "$(COLOUR_YELLOW)Import 'ODyS-TIG - MONC_$(LABEL).json' Grafana Dashboard...$(COLOUR_END)"
	@echo -e "$(COLOUR_YELLOW)-------------------------$(COLOUR_END)"
	@jq -n --argjson dash "$$(cat grafana/provisioning/dashboards/ODyS-TIG\ -\ MONC_$(LABEL).json)" \
         '{dashboard: $$dash, folderId: 0, overwrite: true}' \
      | jq --arg title "ODyS-TIG - MONC - $(LABEL)" '.dashboard.id = "" | .dashboard.uid = "" | .dashboard.title = $$title' \
      | curl -s -o /dev/null -X POST -H "Content-Type: application/json" \
             -u $(GF_SECURITY_ADMIN_USER):$(GF_SECURITY_ADMIN_PASSWORD) \
             "http://localhost:3000/api/dashboards/db" \
             -d @- ;
endif

ifeq ($(TYPE),pload)
	@echo -e "$(COLOUR_YELLOW)-------------------------$(COLOUR_END)"
	@echo -e "$(COLOUR_YELLOW)Import 'ODyS-TIG - MOP_$(LABEL).json' Grafana Dashboard...$(COLOUR_END)"
	@echo -e "$(COLOUR_YELLOW)-------------------------$(COLOUR_END)"
	@jq -n --argjson dash "$$(cat grafana/provisioning/dashboards/ODyS-TIG\ -\ MOP_$(LABEL).json)" \
         '{dashboard: $$dash, folderId: 0, overwrite: true}' \
      | jq --arg title "ODyS-TIG - MOP - $(LABEL)" '.dashboard.id = "" | .dashboard.uid = "" | .dashboard.title = $$title' \
      | curl -s -o /dev/null -X POST -H "Content-Type: application/json" \
             -u $(GF_SECURITY_ADMIN_USER):$(GF_SECURITY_ADMIN_PASSWORD) \
             "http://localhost:3000/api/dashboards/db" \
             -d @- ;
endif

mtextract: ## 📜 Extract-Type 
ifndef TYPE
	@echo -e "$(COLOUR_RED)ERROR:$(COLOUR_END) TYPE= is undefined, must be 'tocpu' or 'cload' or 'pload' or 'nload', exiting..."
	exit 1
endif

ifneq ($(TYPE),tocpu)
  ifneq ($(TYPE),cload)
    ifneq ($(TYPE),pload)
      ifneq ($(TYPE),nload)
			@echo -e "$(COLOUR_RED)ERROR:$(COLOUR_END) TYPE= is not valid, must be 'tocpu' or 'cload' or 'pload' or 'nload', exiting..."
			exit 1
       endif
     endif
   endif
endif

ifndef LABEL
	@echo -e "$(COLOUR_RED)ERROR:$(COLOUR_END) LABEL= is undefined, exiting..."
	exit 1
endif

	@echo
	@echo -e "$(COLOUR_YELLOW)-------------------------$(COLOUR_END)"
	@echo -e "$(COLOUR_YELLOW)Extracting $(TYPE) data...$(COLOUR_END)"
	@echo -e "$(COLOUR_YELLOW)-------------------------$(COLOUR_END)"
	$(CONTAINER_ENGINE) run --rm \
    -v "$(ROOTDIR)/odys_logs:/odys_logs:z" \
    -v "$(ROOTDIR)/odys_csv:/odys_csv:z" \
    --name odys-chart \
    odys-chart \
    $(ODYSCHART_PATH) \
        --$(TYPE) \
        --csv --nochart \
        --log ./odys_logs/$(LOG) \
        --out ./odys_csv/odys_csv_new \
        --label $(TYPE)_$(LABEL)
	@chmod 666 ./odys_csv/odys_csv_new/*

	@echo

ifneq ($(TYPE),pload)
	@echo -e "$(COLOUR_YELLOW)-------------------------$(COLOUR_END)"
	@echo -e "$(COLOUR_YELLOW)Setting-Up 'ODyS-TIG - MONC_$(LABEL).json' Grafana Dashboard...$(COLOUR_END)"
	@echo -e "$(COLOUR_YELLOW)-------------------------$(COLOUR_END)"
	@cp 'grafana/provisioning/dashboards/ODyS-TIG - MONC.json' 'grafana/provisioning/dashboards/ODyS-TIG - MONC_$(LABEL).json'
	@sed -i s/dynamicscaling-chart_ocpu.csv/dynamicscaling-chart_tocpu_$(LABEL).csv/g 'grafana/provisioning/dashboards/ODyS-TIG - MONC_$(LABEL).json'
	@sed -i s/dynamicscaling-chart_nload.csv/dynamicscaling-chart_nload_$(LABEL).csv/g 'grafana/provisioning/dashboards/ODyS-TIG - MONC_$(LABEL).json'
	@sed -i s/dynamicscaling-chart_cload.csv/dynamicscaling-chart_cload_$(LABEL).csv/g 'grafana/provisioning/dashboards/ODyS-TIG - MONC_$(LABEL).json'
	@sed -i s/Current/Target/g 'grafana/provisioning/dashboards/ODyS-TIG - MONC_$(LABEL).json'
	@sed -i s/'ODyS-TIG - MONC'/'ODyS-TIG - MONC - $(LABEL)'/g 'grafana/provisioning/dashboards/ODyS-TIG - MONC_$(LABEL).json'
endif

ifeq ($(TYPE),pload)
	@echo -e "$(COLOUR_YELLOW)-------------------------$(COLOUR_END)"
	@echo -e "$(COLOUR_YELLOW)Setting-Up 'ODyS-TIG - MOP_$(LABEL).json' Grafana Dashboard...$(COLOUR_END)"
	@echo -e "$(COLOUR_YELLOW)-------------------------$(COLOUR_END)"
	@cp 'grafana/provisioning/dashboards/ODyS-TIG - MOP.json' 'grafana/provisioning/dashboards/ODyS-TIG - MOP_$(LABEL).json'
	@sed -i s/dynamicscaling-chart_ocpu.csv/dynamicscaling-chart_tocpu_$(LABEL).csv/g 'grafana/provisioning/dashboards/ODyS-TIG - MOP_$(LABEL).json'
	@sed -i s/dynamicscaling-chart_pload.csv/dynamicscaling-chart_pload_$(LABEL).csv/g 'grafana/provisioning/dashboards/ODyS-TIG - MOP_$(LABEL).json'
	@sed -i s/Current/Target/g 'grafana/provisioning/dashboards/ODyS-TIG - MOP_$(LABEL).json'
	@sed -i s/'ODyS-TIG - MOP'/'ODyS-TIG - MOP - $(LABEL)'/g 'grafana/provisioning/dashboards/ODyS-TIG - MOP_$(LABEL).json'
endif

	@echo

ifneq ($(TYPE),pload)
	@echo -e "$(COLOUR_YELLOW)-------------------------$(COLOUR_END)"
	@echo -e "$(COLOUR_YELLOW)Import 'ODyS-TIG - MONC_$(LABEL).json' Grafana Dashboard...$(COLOUR_END)"
	@echo -e "$(COLOUR_YELLOW)-------------------------$(COLOUR_END)"
	@jq -n --argjson dash "$$(cat grafana/provisioning/dashboards/ODyS-TIG\ -\ MONC_$(LABEL).json)" \
         '{dashboard: $$dash, folderId: 0, overwrite: true}' \
      | jq --arg title "ODyS-TIG - MONC - $(LABEL)" '.dashboard.id = "" | .dashboard.uid = "" | .dashboard.title = $$title' \
      | curl -s -o /dev/null -X POST -H "Content-Type: application/json" \
             -u $(GF_SECURITY_ADMIN_USER):$(GF_SECURITY_ADMIN_PASSWORD) \
             "http://localhost:3000/api/dashboards/db" \
             -d @- 
endif

ifeq ($(TYPE),pload)
	@echo -e "$(COLOUR_YELLOW)-------------------------$(COLOUR_END)"
	@echo -e "$(COLOUR_YELLOW)Import 'ODyS-TIG - MOP_$(LABEL).json' Grafana Dashboard...$(COLOUR_END)"
	@echo -e "$(COLOUR_YELLOW)-------------------------$(COLOUR_END)"
	@jq -n --argjson dash "$$(cat grafana/provisioning/dashboards/ODyS-TIG\ -\ MOP_$(LABEL).json)" \
         '{dashboard: $$dash, folderId: 0, overwrite: true}' \
      | jq --arg title "ODyS-TIG - MOP - $(LABEL)" '.dashboard.id = "" | .dashboard.uid = "" | .dashboard.title = $$title' \
      | curl -s -o /dev/null -X POST -H "Content-Type: application/json" \
             -u $(GF_SECURITY_ADMIN_USER):$(GF_SECURITY_ADMIN_PASSWORD) \
             "http://localhost:3000/api/dashboards/db" \
             -d @- ;
endif
###############################################################################
# End Of File                                                                 #
###############################################################################
