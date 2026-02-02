# Moltbot Docker Image
# Multi-instance container for running moltbot gateway

FROM node:24-slim

# Install dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user (matches existing setup)
RUN useradd -m -s /bin/bash clawd

# Install moltbot globally
# Try official installer first, fallback to npm
RUN curl -fsSL https://molt.bot/install.sh | bash -s -- --no-setup 2>/dev/null || \
    npm install -g clawdbot@latest

# Create symlink for convenience
RUN ln -sf $(which clawdbot || echo /usr/local/bin/clawdbot) /usr/local/bin/moltbot

# Create data directories
RUN mkdir -p /home/clawd/.clawdbot /home/clawd/.gog /home/clawd/moltbot && \
    chown -R clawd:clawd /home/clawd

# Switch to non-root user
USER clawd
WORKDIR /home/clawd/moltbot

# Default port (can be overridden)
ENV MOLTBOT_PORT=18789

# Health check
HEALTHCHECK --interval=30s --timeout=10s --retries=3 \
    CMD curl -sf http://127.0.0.1:${MOLTBOT_PORT}/health || exit 1

# Gateway binds to loopback only (security)
ENTRYPOINT ["moltbot"]
CMD ["gateway", "--bind", "loopback", "--port", "18789"]
