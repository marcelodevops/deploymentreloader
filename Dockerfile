FROM bitnami/kubectl:latest

# Install bash, coreutils, jq
USER root
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
    bash \
    coreutils \
    jq \
 && rm -rf /var/lib/apt/lists/*

# Copy the script
COPY auto-discover-reloader.sh /usr/local/bin/auto-discover-reloader.sh
RUN chmod +x /usr/local/bin/auto-discover-reloader.sh

ENTRYPOINT ["/usr/local/bin/auto-discover-reloader.sh"]
