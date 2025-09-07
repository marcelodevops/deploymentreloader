FROM bitnami/kubectl:latest

# Install bash, coreutils, jq
RUN install_packages bash coreutils jq

# Copy the script
COPY auto-discover-reloader.sh /usr/local/bin/auto-discover-reloader.sh
RUN chmod +x /usr/local/bin/auto-discover-reloader.sh

ENTRYPOINT ["/usr/local/bin/auto-discover-reloader.sh"]
