# Define the Repo and token as parameters

# Use the official Ubuntu base image
FROM ubuntu:latest

# Install Java (required for JMeter), wget, and unzip
RUN apt-get update -qq && \
    apt-get install -y -qq wget curl jq vim ssh && \
    apt-get clean -qq

# Install OpenSSL and ICU libraries manually
# These versions are required for the actions runner to work properly

COPY Dockerfiles/local-runner/lib*.deb /tmp/

# RUN wget --quiet http://archive.ubuntu.com/ubuntu/pool/main/o/openssl/libssl1.1_1.1.1f-1ubuntu2.24_amd64.deb && \
RUN dpkg -i /tmp/libssl1.1_1.1.1f-1ubuntu2.24_amd64.deb && \
     rm /tmp/libssl1.1_1.1.1f-1ubuntu2.24_amd64.deb

# RUN wget --quiet http://security.ubuntu.com/ubuntu/pool/main/i/icu/libicu70_70.1-2ubuntu1_amd64.deb && \
RUN dpkg -i /tmp/libicu70_70.1-2ubuntu1_amd64.deb && \
     rm /tmp/libicu70_70.1-2ubuntu1_amd64.deb

# Performan actions as ubuntu user
USER ubuntu
ARG VERSION=2.328.0

# Set the version of the GitHub Actions Runner
# Default to version 2.325.0 if not specified
RUN cd /home/ubuntu && \
    mkdir actions-runner && cd actions-runner && \
    curl -s -f -o actions-runner-linux-x64-${VERSION}.tar.gz -L https://github.com/actions/runner/releases/download/v${VERSION}/actions-runner-linux-x64-${VERSION}.tar.gz && \
    tar xzf ./actions-runner-linux-x64-${VERSION}.tar.gz

# Generate ssh-key for user ubuntu
RUN ssh-keygen -q -t rsa -b 4096 -N "" -f ~/.ssh/id_rsa 

# Switch back to root
USER root

# Copy know_hosts (servers) and config file to local-runner
COPY Dockerfiles/local-runner/known_hosts /home/ubuntu/.ssh
RUN chmod 600 /home/ubuntu/.ssh/known_hosts && \
    chown ubuntu:ubuntu /home/ubuntu/.ssh/known_hosts
COPY Dockerfiles/local-runner/config /home/ubuntu/.ssh
RUN chmod 600 /home/ubuntu/.ssh/config && \
    chown ubuntu:ubuntu /home/ubuntu/.ssh/config

# Copy scripts to local-runner
COPY shell/run-test.sh /home/ubuntu/run-test.sh 
RUN chmod 700 /home/ubuntu/run-test.sh && \
    chown ubuntu:ubuntu /home/ubuntu/run-test.sh
COPY shell/run-test-lib.sh /home/ubuntu/run-test-lib.sh 
RUN chmod 700 /home/ubuntu/run-test-lib.sh && \
    chown ubuntu:ubuntu /home/ubuntu/run-test-lib.sh
COPY shell/cleanup-remote-job.sh /home/ubuntu/cleanup-remote-job.sh 
RUN chmod 700 /home/ubuntu/cleanup-remote-job.sh && \
    chown ubuntu:ubuntu /home/ubuntu/cleanup-remote-job.sh

# Install dependencies
RUN /home/ubuntu/actions-runner/bin/installdependencies.sh

# Performan actions as ubuntu user
USER ubuntu

ARG GITHUB_REPO_URL
ARG GITHUB_TOKEN
ARG RUNNER_NAME
ARG TAGS="self-hosted"
ARG VAULT_TOKEN
ARG VAULT_URL="http://dcvx-jmtapp-g1:8200/v1/ssh/sign"
ARG VAULT_ROLE="ptp-ssh-role"

RUN PUBKEY=$(cat /home/ubuntu/.ssh/id_rsa.pub) && \
	curl -s --header "X-Vault-Token: ${VAULT_TOKEN}" \
     		--request POST \
     		--data "{\"public_key\":\"$PUBKEY\", \"valid_principals\":\"jmeter\"}" \
     		"${VAULT_URL}/${VAULT_ROLE}" | jq -r '.data.signed_key' > /home/ubuntu/.ssh/id_rsa_cert.pub

# Configure Local Runner
RUN cd /home/ubuntu/actions-runner && ./config.sh --unattended \
        --url ${GITHUB_REPO_URL} \
        --token ${GITHUB_TOKEN} \
        --name ${RUNNER_NAME} \
        --labels ${TAGS} \
        -local-runner \
        --work /home/ubuntu/work

# Run Local Runner
CMD ["/home/ubuntu/actions-runner/run.sh"]
