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
#    rcitton     01/26/26 - Refactored for DRY principles
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
	COMPOSE_ROOT = /ODyS-TIG
	HOST_PROJECT_PATH = $(MACOS_HOST_PROJECT_PATH)
else
	COMPOSE_ROOT = $(ROOTDIR)
	HOST_PROJECT_PATH = $(ROOTDIR)
endif

# Variable for the temporary file
DATASOURCE_TEMP_FILE = $(HOST_PROJECT_PATH)/grafana/provisioning/datasources/datasource.yml.tmp

# ----------------------------------------------------------------------------------
SHELL=/bin/bash
ROOTDIR=$(PWD)
ODYSCHART_PATH="/opt/dynamicscaling-chart/dynamicscaling-chart.bin"
ODYSCHARTRPM_PATH=./odys_chart/dynamicscaling-chart-*.rpm

# Valid TYPE values for extraction targets
VALID_TYPES_MEXTRACT  := cocpu cload pload nload
VALID_TYPES_MTEXTRACT := tocpu cload pload nload

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
## Container names       ##
###########################
CONTAINERS := odys-grafana odys-telegraf odys-influxdb

###############################################################################
#  REUSABLE FUNCTIONS                                                         #
###############################################################################

# Print section header
define print_header
	@echo -e "$(COLOUR_YELLOW)-------------------------$(COLOUR_END)"
	@echo -e "$(COLOUR_YELLOW)$(1)$(COLOUR_END)"
	@echo -e "$(COLOUR_YELLOW)-------------------------$(COLOUR_END)"
endef

# Print info message
define print_info
	@echo -e "$(COLOUR_BLUE)...$(1)$(COLOUR_END)"
endef

# Print success message
define print_success
	@echo -e "$(COLOUR_GREEN)$(1)$(COLOUR_END)"
endef

# Run odys-chart extraction
# $(1) = display name, $(2) = chart flag
define run_extraction
	$(call print_header,📈 Extracting $(1) data...)
	$(CONTAINER_ENGINE) run --rm \
		-v "$(ROOTDIR)/odys_logs:/odys_logs:z" \
		-v "$(ROOTDIR)/odys_csv:/odys_csv:z" \
		--name odys-chart \
		odys-chart \
		$(ODYSCHART_PATH) \
			--$(2) \
			--csv \
			--nochart \
			--log ./odys_logs/dynamicscaling.log \
			--out ./odys_csv/odys_csv_new
	@chmod 666 ./odys_csv/odys_csv_new/*
endef

# Run odys-chart extraction with label
# $(1) = chart flag, $(2) = log file, $(3) = label
define run_extraction_labeled
	$(CONTAINER_ENGINE) run --rm \
		-v "$(ROOTDIR)/odys_logs:/odys_logs:z" \
		-v "$(ROOTDIR)/odys_csv:/odys_csv:z" \
		--name odys-chart \
		odys-chart \
		$(ODYSCHART_PATH) \
			--$(1) \
			--csv --nochart \
			--log ./odys_logs/$(2) \
			--out ./odys_csv/odys_csv_new \
			--label $(1)_$(3)
	@chmod 666 ./odys_csv/odys_csv_new/*
endef

# Setup dashboard JSON file
# $(1) = dashboard type (MONC or MOP), $(2) = label, $(3) = ocpu replacement prefix
define setup_dashboard
	$(call print_info,Setting-Up 'ODyS-TIG - $(1)_$(2).json' Grafana Dashboard...)
	@cp 'grafana/provisioning/dashboards/ODyS-TIG - $(1).json' 'grafana/provisioning/dashboards/ODyS-TIG - $(1)_$(2).json'
	@sed -i $(SED_INPLACE_EXT) 's/dynamicscaling-chart_ocpu.csv/dynamicscaling-chart_$(3)_$(2).csv/g' 'grafana/provisioning/dashboards/ODyS-TIG - $(1)_$(2).json'
endef

# Import dashboard to Grafana
# $(1) = dashboard type (MONC or MOP), $(2) = label
define import_dashboard
	$(call print_info,Import 'ODyS-TIG - $(1)_$(2).json' Grafana Dashboard...)
	@jq -n --argjson dash "$$(cat grafana/provisioning/dashboards/ODyS-TIG\ -\ $(1)_$(2).json)" \
		'{dashboard: $$dash, folderId: 0, overwrite: true}' \
		| jq --arg title "ODyS-TIG - $(1) - $(2)" '.dashboard.id = "" | .dashboard.uid = "" | .dashboard.title = $$title' \
		| curl -s -o /dev/null -X POST -H "Content-Type: application/json" \
			-u $(GF_SECURITY_ADMIN_USER):$(GF_SECURITY_ADMIN_PASSWORD) \
			"http://localhost:3000/api/dashboards/db" \
			-d @-
endef

# Common cleanup operations
define cleanup_common
	$(call print_info,stopping ODyS-TIG compose)
	-@$(CONTAINER_COMPOSE) stop >/dev/null 2>&1 || true
	@echo
	$(call print_info,removing ODyS-TIG containers)
	@if echo "$(CONTAINER_ENGINE)" | grep -q docker; then \
		$(CONTAINER_COMPOSE) rm --force -v >/dev/null 2>&1 || true; \
	else \
		for c in $(CONTAINERS); do \
			$(CONTAINER_ENGINE) rm -f $$c >/dev/null 2>&1 || true; \
		done; \
	fi
	@if echo "$(CONTAINER_ENGINE)" | grep -q podman; then \
		echo -e "$(COLOUR_BLUE)...removing volumes & network$(COLOUR_END)"; \
		$(CONTAINER_ENGINE) volume ls -qf dangling=true 2>/dev/null | xargs -r $(CONTAINER_ENGINE) volume rm >/dev/null 2>&1 || true; \
		$(CONTAINER_ENGINE) network rm $$($(CONTAINER_ENGINE) network ls --filter=name='odys*' -q 2>/dev/null) >/dev/null 2>&1 || true; \
	fi
	@echo
	$(call print_info,removing csv entries)
	@-rm -f ./odys_csv/odys_csv_new/*
	@-rm -f ./odys_csv/odys_csv_old/*
	@-rm -f ./odys_csv/odys_csv_err/*
	@echo
	$(call print_info,removing dashboards entries)
	@-rm -f ./grafana/provisioning/dashboards/ODyS-TIG\ -\ MONC_*.json
	@-rm -f ./grafana/provisioning/dashboards/ODyS-TIG\ -\ MOP_*.json
	@echo
	$(call print_info,removing telegraf log)
	@-rm -f ./telegraf/log/*
endef

###########################
## Help Setup            ##
###########################
.DEFAULT_GOAL := help
.PHONY: help setup cleanup cleanupall start stop status ct ci cg \
        monc mop ocpu nload cload pload mextract mtextract \
        reset_monc reset_mop setup_monc setup_mop

help:
	@echo -e "$(COLOUR_GREEN)-----------------------------------------------------------------------$(COLOUR_END)"
	@echo -e "$(COLOUR_GREEN) ODyS-TIG: Dynamic Scaling Monitoring Stack (Telegraf,InfluxDB,Grafana)$(COLOUR_END)"
	@echo -e "$(COLOUR_GREEN) Version 3.0.0$(COLOUR_END)"
	@echo -e "$(COLOUR_GREEN) Author: Ruggero Citton$(COLOUR_END)"
	@echo -e "$(COLOUR_GREEN) RAC Pack, Cloud Innovation & Solution Engineering Team$(COLOUR_END)"
	@echo -e "$(COLOUR_GREEN)-----------------------------------------------------------------------$(COLOUR_END)"
	@echo
	@echo -e "$(COLOUR_YELLOW)                        Available Commands$(COLOUR_END)"
	@echo "-----------------------------------------------------------------------"
	@echo "        Command                    Action"
	@echo "-----------------------------------------------------------------------"
	@echo "🔧  make setup        ➜  Setup          ODyS-TIG"
	@echo "🔧  make setup_monc   ➜  Setup+Measure  ocpu,nload,cload"
	@echo "🔧  make setup_mop    ➜  Setup+Measure  ocpu,pload"
	@echo "-----------------------------------------------------------------------"
	@echo "🦭  make ct           ➜  Connect        Telegraf-container"
	@echo "🦭  make ci           ➜  Connect        Influxdb-container"
	@echo "🦭  make cg           ➜  Connect        Grafana-container"
	@echo "-----------------------------------------------------------------------"
	@echo "🚀  make start        ➜  Start          ODyS-TIG"
	@echo "🛑  make stop         ➜  Stop           ODyS-TIG"
	@echo "🔎  make status       ➜  Status         ODyS-TIG"
	@echo "-----------------------------------------------------------------------"
	@echo "📈  make monc         ➜  Measure        ocpu,nload,cload"
	@echo "📈  make mop          ➜  Measure        ocpu,pload"
	@echo "📈  make ocpu         ➜  Measure        ocpu"
	@echo "📈  make nload        ➜  Measure        nload"
	@echo "📈  make cload        ➜  Measure        cload"
	@echo "📈  make pload        ➜  Measure        pload"
	@echo "-----------------------------------------------------------------------"
	@echo "📜  make mextract     ➜  Extract (TYPE=cocpu|cload|pload|nload)"
	@echo "📜  make mtextract    ➜  Extract (TYPE=tocpu|cload|pload|nload)"
	@echo "-----------------------------------------------------------------------"
	@echo "♻️   make reset_monc   ➜  Reset+Measure  ocpu,nload,cload"
	@echo "♻️   make reset_mop    ➜  Reset+Measure  ocpu,pload"
	@echo "-----------------------------------------------------------------------"
	@echo "🧹  make cleanup      ➜  Cleanup        ODyS-TIG containers"
	@echo "🧹  make cleanupall   ➜  Cleanup        ODyS-TIG containers & images"
	@echo "-----------------------------------------------------------------------"
	@echo

###############################################################################
#  MACRO SECTION                                                              #
###############################################################################

reset_monc: cleanup setup_monc
reset_mop: cleanup setup_mop
setup_monc: setup monc
setup_mop: setup mop

###############################################################################
#  MAIN CONTAINERS SECTION                                                    #
###############################################################################

setup:
	$(call print_header,🔧 Making the ODyS-TIG...)
ifeq (,$(wildcard $(ODYSCHARTRPM_PATH)))
	@echo -e "$(COLOUR_RED)Missing dynamicscaling-chart.rpm$(COLOUR_END)"
	@exit 1
endif
ifdef PROXY
	$(call print_info,setting proxy env variables)
	@export HTTPS_PROXY=$(PROXY) HTTP_PROXY=$(PROXY) \
		NO_PROXY="localhost,127.0.0.1,/var/run/docker.sock" \
		http_proxy=$(PROXY) https_proxy=$(PROXY) \
		no_proxy="localhost,127.0.0.1,/var/run/docker.sock"
else
	$(call print_info,proxy not defined)
endif
	@echo
	$(call print_info,making odys-chart container)
	$(CONTAINER_ENGINE) build -t odys-chart ./
	@echo
	$(call print_info,setting permissions for telegraf directories)
	@chmod 777 ./odys_csv/odys_csv_new ./odys_csv/odys_csv_old ./odys_csv/odys_csv_err ./telegraf/log
	@echo
	$(call print_info,making ODyS-TIG compose)
	@TIG_ROOT=$(COMPOSE_ROOT) $(CONTAINER_COMPOSE) -f compose.yml --env-file config.env up -d
	@sleep 10
	@echo
	$(call print_info,setup grafana container)
	$(CONTAINER_ENGINE) stop odys-grafana
	@cp $(HOST_PROJECT_PATH)/grafana/provisioning/datasources/datasource.yml $(DATASOURCE_TEMP_FILE)
	@sed -i $(SED_INPLACE_EXT) 's|PLACEHOLDER_INFLUXDB_ORG|$(INFLUXDB_INIT_ORG)|g' $(DATASOURCE_TEMP_FILE)
	@sed -i $(SED_INPLACE_EXT) 's|PLACEHOLDER_INFLUXDB_TOKEN|"Token $(INFLUXDB_INIT_ADMIN_TOKEN)"|g' $(DATASOURCE_TEMP_FILE)
	@$(CONTAINER_ENGINE) cp $(DATASOURCE_TEMP_FILE) odys-grafana:/etc/grafana/provisioning/datasources/datasource.yml
	$(CONTAINER_ENGINE) start odys-grafana
	@sleep 5
	$(call print_success,-----------------------------------------------------------)
	$(call print_success,✅ ODyS-TIG is ready. Browse to http://localhost:3000)
	$(call print_success,-----------------------------------------------------------)

cleanup:
	$(call print_header,🧹 Cleaning up ODyS-TIG...)
	$(call cleanup_common)
	$(call print_success,---------------------------)
	$(call print_success,✅ ODyS-TIG cleanup done!)
	$(call print_success,---------------------------)

cleanupall:
	$(call print_header,🧹 Cleaning up ODyS-TIG (full)...)
	$(call print_info,removing odys-chart image)
	@-$(CONTAINER_ENGINE) rmi odys-chart 2>/dev/null || true
	@echo
	$(call cleanup_common)
	@echo
	$(call print_info,removing tig images)
	@if echo "$(CONTAINER_ENGINE)" | grep -q podman; then \
		$(CONTAINER_ENGINE) rmi container-registry.oracle.com/os/oraclelinux:8-slim docker.io/library/telegraf docker.io/library/influxdb:2.7 docker.io/grafana/grafana --force 2>/dev/null || true; \
	else \
		$(CONTAINER_ENGINE) rmi oraclelinux:8-slim telegraf influxdb:2.7 grafana/grafana --force 2>/dev/null || true; \
	fi
	$(call print_success,---------------------------)
	$(call print_success,✅ ODyS-TIG cleanup done!)
	$(call print_success,---------------------------)

start:
	$(call print_header,🚀 Starting ODyS-TIG...)
	@$(CONTAINER_COMPOSE) start
	$(call print_success,-----------------------------------------------------------)
	$(call print_success,✅ ODyS-TIG is ready. Browse to http://localhost:3000)
	$(call print_success,-----------------------------------------------------------)

stop:
	$(call print_header,🛑 Stopping ODyS-TIG...)
	@$(CONTAINER_COMPOSE) stop

status:
	$(call print_header,🔎 ODyS-TIG Status)
	$(call print_info,ODyS-TIG containers)
	@$(CONTAINER_ENGINE) container ls --filter "name=odys*"
	@echo
	$(call print_info,ODyS-TIG images)
	@$(CONTAINER_ENGINE) images --filter reference="*telegraf" --filter reference="*influxdb" --filter reference="*grafana/grafana" --filter reference="*odys-chart"

ct:
	$(call print_info,🦭 Connecting to telegraf...)
	@$(CONTAINER_ENGINE) exec -it odys-telegraf bash

ci:
	$(call print_info,🦭 Connecting to influxdb...)
	@$(CONTAINER_ENGINE) exec -it odys-influxdb bash

cg:
	$(call print_info,🦭 Connecting to grafana...)
	@$(CONTAINER_ENGINE) exec -it odys-grafana bash

###############################################################################
# ODyS CHART SECTION - Measurement Targets                                    #
###############################################################################

monc: ocpu nload cload
	$(call print_success,-----------------------------------------------------------)
	$(call print_success,✅ ODyS-TIG measure ready!)
	$(call print_success,-----------------------------------------------------------)

mop: ocpu pload
	$(call print_success,-----------------------------------------------------------)
	$(call print_success,✅ ODyS-TIG measure ready!)
	$(call print_success,-----------------------------------------------------------)

ocpu:
	$(call run_extraction,OCPU,cocpu)

nload:
	$(call run_extraction,Node Load,nload)

cload:
	$(call run_extraction,Cluster Load,cload)

pload:
	$(call run_extraction,Plugin Load,pload)

###############################################################################
# ODyS CHART SECTION - Extract Targets                                        #
###############################################################################

mextract:
ifndef TYPE
	$(error TYPE is undefined. Valid values: $(VALID_TYPES_MEXTRACT))
endif
ifeq ($(filter $(TYPE),$(VALID_TYPES_MEXTRACT)),)
	$(error TYPE='$(TYPE)' is invalid. Valid values: $(VALID_TYPES_MEXTRACT))
endif
ifndef LABEL
	$(error LABEL is undefined)
endif
	@echo
	$(call print_header,📜 Extracting $(TYPE) data...)
	$(call run_extraction_labeled,$(TYPE),$(LOG),$(LABEL))
	@echo
ifeq ($(TYPE),pload)
	$(call setup_dashboard,MOP,$(LABEL),cocpu)
	@sed -i $(SED_INPLACE_EXT) 's/dynamicscaling-chart_pload.csv/dynamicscaling-chart_pload_$(LABEL).csv/g' 'grafana/provisioning/dashboards/ODyS-TIG - MOP_$(LABEL).json'
	@sed -i $(SED_INPLACE_EXT) "s/'ODyS-TIG - MOP'/'ODyS-TIG - MOP - $(LABEL)'/g" 'grafana/provisioning/dashboards/ODyS-TIG - MOP_$(LABEL).json'
	@echo
	$(call import_dashboard,MOP,$(LABEL))
else
	$(call setup_dashboard,MONC,$(LABEL),cocpu)
	@sed -i $(SED_INPLACE_EXT) 's/dynamicscaling-chart_nload.csv/dynamicscaling-chart_nload_$(LABEL).csv/g' 'grafana/provisioning/dashboards/ODyS-TIG - MONC_$(LABEL).json'
	@sed -i $(SED_INPLACE_EXT) 's/dynamicscaling-chart_cload.csv/dynamicscaling-chart_cload_$(LABEL).csv/g' 'grafana/provisioning/dashboards/ODyS-TIG - MONC_$(LABEL).json'
	@sed -i $(SED_INPLACE_EXT) "s/'ODyS-TIG - MONC'/'ODyS-TIG - MONC - $(LABEL)'/g" 'grafana/provisioning/dashboards/ODyS-TIG - MONC_$(LABEL).json'
	@echo
	$(call import_dashboard,MONC,$(LABEL))
endif

mtextract:
ifndef TYPE
	$(error TYPE is undefined. Valid values: $(VALID_TYPES_MTEXTRACT))
endif
ifeq ($(filter $(TYPE),$(VALID_TYPES_MTEXTRACT)),)
	$(error TYPE='$(TYPE)' is invalid. Valid values: $(VALID_TYPES_MTEXTRACT))
endif
ifndef LABEL
	$(error LABEL is undefined)
endif
	@echo
	$(call print_header,📜 Extracting $(TYPE) data...)
	$(call run_extraction_labeled,$(TYPE),$(LOG),$(LABEL))
	@echo
ifeq ($(TYPE),pload)
	$(call setup_dashboard,MOP,$(LABEL),tocpu)
	@sed -i $(SED_INPLACE_EXT) 's/dynamicscaling-chart_pload.csv/dynamicscaling-chart_pload_$(LABEL).csv/g' 'grafana/provisioning/dashboards/ODyS-TIG - MOP_$(LABEL).json'
	@sed -i $(SED_INPLACE_EXT) 's/Current/Target/g' 'grafana/provisioning/dashboards/ODyS-TIG - MOP_$(LABEL).json'
	@sed -i $(SED_INPLACE_EXT) "s/'ODyS-TIG - MOP'/'ODyS-TIG - MOP - $(LABEL)'/g" 'grafana/provisioning/dashboards/ODyS-TIG - MOP_$(LABEL).json'
	@echo
	$(call import_dashboard,MOP,$(LABEL))
else
	$(call setup_dashboard,MONC,$(LABEL),tocpu)
	@sed -i $(SED_INPLACE_EXT) 's/dynamicscaling-chart_nload.csv/dynamicscaling-chart_nload_$(LABEL).csv/g' 'grafana/provisioning/dashboards/ODyS-TIG - MONC_$(LABEL).json'
	@sed -i $(SED_INPLACE_EXT) 's/dynamicscaling-chart_cload.csv/dynamicscaling-chart_cload_$(LABEL).csv/g' 'grafana/provisioning/dashboards/ODyS-TIG - MONC_$(LABEL).json'
	@sed -i $(SED_INPLACE_EXT) 's/Current/Target/g' 'grafana/provisioning/dashboards/ODyS-TIG - MONC_$(LABEL).json'
	@sed -i $(SED_INPLACE_EXT) "s/'ODyS-TIG - MONC'/'ODyS-TIG - MONC - $(LABEL)'/g" 'grafana/provisioning/dashboards/ODyS-TIG - MONC_$(LABEL).json'
	@echo
	$(call import_dashboard,MONC,$(LABEL))
endif

###############################################################################
# End Of File                                                                 #
###############################################################################
