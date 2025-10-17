FROM  ghcr.io/actions/actions-runner:2.328.0

# Install custom tools
USER root
RUN apt-get update && apt-get install -y wget curl jq vim ssh

# Switch back to runner user
USER runner

# Generate ssh-key for user runner
RUN ssh-keygen -q -t rsa -b 4096 -N "" -f ~/.ssh/id_rsa 

# Switch back to root
USER root

# Copy know_hosts (servers) and config file to local-runner
COPY Dockerfiles/arc-custom-runner/known_hosts /home/runner/.ssh
RUN chmod 600 /home/runner/.ssh/known_hosts && \
    chown runner:runner /home/runner/.ssh/known_hosts
COPY Dockerfiles/arc-custom-runner/config /home/runner/.ssh
RUN chmod 600 /home/runner/.ssh/config && \
    chown runner:runner /home/runner/.ssh/config

# Copy scripts to local-runner
COPY ./shell/run-test.sh /home/runner/run-test.sh 
RUN chmod 700 /home/runner/run-test.sh && \
    chown runner:runner /home/runner/run-test.sh
COPY ./shell/run-test-lib.sh /home/runner/run-test-lib.sh 
RUN chmod 700 /home/runner/run-test-lib.sh && \
    chown runner:runner /home/runner/run-test-lib.sh
COPY ./shell/cleanup-remote-job.sh /home/runner/cleanup-remote-job.sh 
RUN chmod 700 /home/runner/cleanup-remote-job.sh && \
    chown runner:runner /home/runner/cleanup-remote-job.sh

# Switch back to runner user
USER runner

ARG VAULT_TOKEN
ARG VAULT_URL="http://dcvx-jmtapp-g1:8200/v1/ssh/sign"
ARG VAULT_ROLE="ptp-ssh-role"

ENV VAULT_TOKEN=${VAULT_TOKEN}
ENV VAULT_URL=${VAULT_URL}
ENV VAULT_ROLE=${VAULT_ROLE}

RUN PUBKEY=$(cat /home/runner/.ssh/id_rsa.pub) && \
	curl -s --header "X-Vault-Token: ${VAULT_TOKEN}" \
     		--request POST \
     		--data "{\"public_key\":\"$PUBKEY\", \"valid_principals\":\"jmeter\"}" \
     		"${VAULT_URL}/${VAULT_ROLE}" | jq -r '.data.signed_key' > /home/runner/.ssh/id_rsa_cert.pub

# Entrypoint remains unchanged
ENTRYPOINT ["/home/runner/run.sh"]
