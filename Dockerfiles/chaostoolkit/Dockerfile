# Use a specific Ubuntu base image
FROM ubuntu:24.04

USER root

# Install Java (required for JMeter), wget, and unzip
RUN apt-get update && \
    apt-get install -y wget unzip curl openssh-client python3 python3-pip python3-venv libcairo2 libcairo2-dev && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

RUN useradd -ms /bin/bash chaos

USER chaos

WORKDIR /home/chaos
ENV PATH="/home/chaos/.local/bin:${PATH}"

# Create a directory for the chaos toolkit
RUN mkdir -p /home/chaos/chaostoolkit

RUN python3 -m venv /home/chaos/chaostoolkit/ && \
    echo ". /home/chaos/chaostoolkit/bin/activate" >> /home/chaos/.bashrc

# Install chaostoolkit, reporting tools, and dependencies
RUN . /home/chaos/chaostoolkit/bin/activate && \
    pip install chaostoolkit && \
    pip install chaostoolkit-reporting && \
    pip install pypandoc-binary && \
    pip install 'chaostoolkit-lib[jsonpath]'
