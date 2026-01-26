# -----------------------------------------------------------------
#
#    NAME
#      Dynamicscaling Telegraf InfluxDB Grafana (ODyS-TIG)
#
#    DESCRIPTION
#      ODyS-TIG dockerfile for ODyS-Chart
#
#    AUTHOR:
#      ruggero.citton@oracle.com
#
#    NOTES
#
#    MODIFIED   (MM/DD/YY)
#    rcitton     01/26/26 - Refactored: LABEL instead of MAINTAINER
#    rcitton     03/16/23 - creation
#
# -----------------------------------------------------------------

# Pull base image
FROM oraclelinux:8-slim

# Modern metadata labels (replaces deprecated MAINTAINER)
LABEL maintainer="ruggero.citton@oracle.com" \
      description="ODyS-Chart container for DynamicScaling metrics extraction" \
      version="3.0.0"

# Environment configuration
ENV TERM=xterm-256color \
    SYSTEMD_OFFLINE=1

# Install required packages
# - gd: Graphics library for chart generation
# - gnuplot: Plotting utility for charts
RUN microdnf -y install oraclelinux-developer-release-el8 && \
    microdnf --enablerepo=ol8_developer --setopt=install_weak_deps=0 install gd gnuplot && \
    microdnf clean all && \
    rm -rf /var/cache/yum/* && \
    sync

# Install DynamicScaling Chart package
COPY ./odys_chart /root
RUN rpm -Uvh --force --nodeps --noscripts /root/*.rpm && \
    rm -f /root/*.rpm && \
    sync

# -----------------------
# EndOfFile
# -----------------------
