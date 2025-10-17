#!/bin/bash

# Check if both parameters are provided
if [ -z "$1" ]; then
  echo "Parameter required: <JMX File>"
  exit 1
fi

# Paths to the files on the host machine
JMX_FILE_NAME="$1"
JMETER_PARAMS="$2"

# Check if the files exist on the host machine
if [ ! -f "/opt/jmeter/staging/$JMX_FILE_NAME" ]; then
  echo "JMX file not found at $JMX_FILE_NAME."
  exit 1
fi

# Run JMeter with the provided JMX file and data file
/opt/jmeter/bin/jmeter -n -t /opt/jmeter/staging/$JMX_FILE_NAME ${JMETER_PARAMS:+$JMETER_PARAMS} -l /opt/jmeter/staging/results.jtl -j /opt/jmeter/staging/jmeter.log -e -o /opt/jmeter/staging/report
