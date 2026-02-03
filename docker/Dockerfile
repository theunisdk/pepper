# OpenClaw Docker Image
# Multi-instance container for running OpenClaw gateway

FROM node:24-slim

# Install dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

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
    mkdir -p /home/clawd/.openclaw /home/clawd/.gog /home/clawd/openclaw && \
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
