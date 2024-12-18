# Base image from Kaniko
FROM gcr.io/kaniko-project/executor:v1.7.0-debug

# Add the Harbor CA certificate
COPY ca.crt /kaniko/ssl/certs/harbor-ca.crt

# Ensure necessary directories exist
RUN mkdir -p /kaniko/.docker

# Default entrypoint
ENTRYPOINT ["/kaniko/executor"]
