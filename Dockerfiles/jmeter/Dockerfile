# Define the JMeter version as a variable
ARG JMETER_VERSION=5.6.3
ARG ROLE=standalone

# Use a specific Ubuntu base image
FROM ubuntu:latest

# Install Java (required for JMeter), wget, and unzip
RUN apt-get update && \
    apt-get install -y openjdk-11-jre wget unzip curl git && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Set JAVA_HOME environment variable
ENV JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64

# Download and extract JMeter
ARG JMETER_VERSION
RUN wget https://downloads.apache.org//jmeter/binaries/apache-jmeter-${JMETER_VERSION}.tgz && \
    tar -xzf apache-jmeter-${JMETER_VERSION}.tgz && \
    mv apache-jmeter-${JMETER_VERSION} /opt/jmeter && \
    rm apache-jmeter-${JMETER_VERSION}.tgz

# Copy all plugins from the "plugins" subdirectory to JMeter's lib/ext directory
COPY plugins/ /opt/jmeter/lib/
COPY PluginsManagerCMD.sh /opt/jmeter/bin/

# Install Custom Thread Plugin
RUN cd /opt/jmeter/bin && \
    chmod +x ./PluginsManagerCMD.sh && \
    ./PluginsManagerCMD.sh install jpgc-casutg

# Create directory for file sharing with host
RUN mkdir -p /opt/jmeter/staging/report

# Test if image is to be client-server ou standalone and configure accordingly
ARG ROLE
RUN if [ "$ROLE" = "client-server" ]; then \
      sed -i 's/^#\?server\.rmi\.ssl\.disable=.*/server.rmi.ssl.disable=true/' /opt/jmeter/bin/jmeter.properties; \
    fi

# Copy the entrypoint script into the container
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Set the entrypoint
ENTRYPOINT ["/entrypoint.sh"]
