# GitLab Backup Container
# Based on Alpine Linux for minimal footprint
FROM alpine:3.20

# Install required packages
RUN apk add --no-cache \
    bash \
    curl \
    rsync \
    openssh-client \
    docker-cli \
    tar \
    gzip \
    findutils \
    coreutils \
    tzdata \
    mailx \
    && rm -rf /var/cache/apk/*

# Set timezone
ENV TZ=Asia/Shanghai

# Create working directory
WORKDIR /app

# Copy scripts
COPY scripts/ /app/scripts/

# Make scripts executable
RUN chmod +x /app/scripts/*.sh

# Create necessary directories
RUN mkdir -p /backups /logs /config

# Default entrypoint
ENTRYPOINT ["/app/scripts/backup.sh"]
