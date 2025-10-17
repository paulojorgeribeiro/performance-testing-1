# Use a specific Ubuntu base image
FROM ubuntu:latest

# Install Java (required for JMeter), wget, and unzip
RUN apt-get update && \
    apt-get install -y wget unzip curl git python3 python3-sqlalchemy python3-psycopg2 python3-fastapi python3-uvicorn python3-hvac && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Copy the application files to container
COPY app/ /root/app/

# Copy the entrypoint script into the container
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Set the entrypoint
ENTRYPOINT ["/entrypoint.sh"]