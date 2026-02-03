# OpenClaw Docker Image
# Multi-instance container for running OpenClaw gateway

FROM node:24-slim

# Install dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    ca-certificates \
    gnupg \
    python3 \
    && rm -rf /var/lib/apt/lists/*

# Install Google Cloud SDK
RUN curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" > /etc/apt/sources.list.d/google-cloud-sdk.list \
    && apt-get update && apt-get install -y --no-install-recommends google-cloud-cli \
    && rm -rf /var/lib/apt/lists/*

# Install gog (Google Suite CLI - Gmail, Calendar, Drive, etc.)
RUN curl -fsSL https://github.com/steipete/gogcli/releases/download/v0.9.0/gogcli_0.9.0_linux_amd64.tar.gz \
    | tar -xz -C /usr/local/bin gog \
    && chmod +x /usr/local/bin/gog

# Create non-root user (matches existing setup)
RUN useradd -m -s /bin/bash clawd

# Install openclaw globally
# Try official installer first, fallback to npm
RUN curl -fsSL https://openclaw.ai/install.sh | bash -s -- --no-setup 2>/dev/null || \
    npm install -g openclaw@latest

# Create data directories and remove legacy .clawdbot if created by installer
# Note: upstream openclaw migrated from .clawdbot to .openclaw
# We must remove .clawdbot to avoid cross-device migration errors with volumes
RUN rm -rf /home/clawd/.clawdbot && \
    mkdir -p /home/clawd/.openclaw /home/clawd/.config/gogcli /home/clawd/openclaw && \
    chown -R clawd:clawd /home/clawd

# Switch to non-root user
USER clawd
WORKDIR /home/clawd/openclaw

# Default port (can be overridden)
ENV OPENCLAW_PORT=18789

# Health check
HEALTHCHECK --interval=30s --timeout=10s --retries=3 \
    CMD curl -sf http://127.0.0.1:${OPENCLAW_PORT}/health || exit 1

# Gateway binds to loopback only (security)
ENTRYPOINT ["openclaw"]
CMD ["gateway", "--bind", "loopback", "--port", "18789"]
