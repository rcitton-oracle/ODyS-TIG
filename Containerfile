# -----------------------------------------------------------------
#
#    NAME
#      Dynamicscaling Telegraf InlfuxDB Grafana (ODyS-TIG)
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
#    rcitton     03/16/23 - creation
#
# -----------------------------------------------------------------

# Pull base image
# ---------------
FROM oraclelinux:8-slim
ENV TERM xterm-256color


# Maintainer
# ----------
MAINTAINER Ruggero Citton <ruggero.citton@oracle.com>


# Setup OCI-cli & required dynamicscaling packages
#-------------------------------------------------
RUN microdnf -y install oraclelinux-developer-release-el8 && \
    microdnf --enablerepo=ol8_developer install gd gnuplot && \
    rm -rf /var/cache/yum/* && \
    sync


# Setup Dynamicscaling packages
#-------------------------------------------------
COPY ./odys_chart /root
RUN rpm -Uvh --force /root/*.rpm &&\
    rm  -f /root/*.rpm  && \
    sync

# -----------------------
# EndOfFile
# -----------------------

