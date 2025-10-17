# Use the official Alpine image as the base image
FROM alpine:latest

# Create a non-root user and group
RUN addgroup -S grafana_group && adduser -S grafana_user -G grafana_group

# Install jq and curl
RUN apk update && apk add --no-cache jq curl inotify-tools

# Download and install kubectl
RUN curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" \
    && chmod +x kubectl \
    && mv kubectl /usr/local/bin/

# Switch to the non-root user
USER grafana_user

# Set the default command to run when the container starts
CMD ["sh"]

