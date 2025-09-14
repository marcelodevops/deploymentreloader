# -------------------------------
# Stage 1: Build environment
# -------------------------------
FROM bitnami/kubectl:latest AS builder

USER root

# Install jq, bash, coreutils into builder
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
    bash \
    coreutils \
    jq \
 && rm -rf /var/lib/apt/lists/*

# Copy script into builder
COPY auto-discover-reloader.sh /usr/local/bin/auto-discover-reloader.sh
RUN chmod +x /usr/local/bin/auto-discover-reloader.sh

# -------------------------------
# Stage 2: Minimal runtime image
# -------------------------------
FROM bitnami/kubectl:latest

USER root

# Copy only what we need from builder
COPY --from=builder /bin/bash /bin/bash
COPY --from=builder /bin/cat /bin/cat
COPY --from=builder /bin/sha256sum /bin/sha256sum
COPY --from=builder /usr/bin/jq /usr/bin/jq
COPY --from=builder /usr/local/bin/auto-discover-reloader.sh /usr/local/bin/auto-discover-reloader.sh

RUN chmod +x /usr/local/bin/auto-discover-reloader.sh

ENTRYPOINT ["/usr/local/bin/auto-discover-reloader.sh"]
