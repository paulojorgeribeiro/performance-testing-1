FROM ubuntu:22.04

# Install dependencies
RUN apt-get update && \
    apt-get install -y curl jq git sudo && \
    rm -rf /var/lib/apt/lists/*

# Create runner user
RUN useradd -m runner && mkdir /actions-runner && chown runner:runner /actions-runner
USER runner
WORKDIR /actions-runner

# Download the GitHub Actions runner binary
RUN curl -O -L https://github.com/actions/runner/releases/download/v2.328.0/actions-runner-linux-x64-2.328.0.tar.gz && \
    tar xzf actions-runner-linux-x64-2.328.0.tar.gz && \
    rm actions-runner-linux-x64-2.328.0.tar.gz

# Copy start script
COPY start.sh /start.sh
ENTRYPOINT ["/start.sh"]

