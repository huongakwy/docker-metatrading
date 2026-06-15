# Dockerfile for MetaTrader 5 Docker Cluster
# Base image with MT5 and VNC pre-installed

FROM gmag11/metatrader5_vnc:1.0

# Maintainer information
LABEL maintainer="MT5 Docker Team"
LABEL description="MetaTrader 5 with automated EA attachment"

# Copy MT5 installer
COPY mt5setup.exe /tmp/mt5setup.exe

# Create user with correct UID/GID (1000:1002) instead of default 911
RUN (groupdel abc 2>/dev/null || true) && \
    (groupmod -g 1002 kasm-user 2>/dev/null || groupadd -g 1002 kasm-user) && \
    (usermod -u 1000 -g 1002 kasm-user 2>/dev/null || useradd -u 1000 -g 1002 -G audio,video -m -s /bin/bash kasm-user)

# Setup Wine prefix and install MetaTrader 5 silently
RUN WINEPREFIX=/config/.wine wineboot --init && \
    WINEPREFIX=/config/.wine wine /tmp/mt5setup.exe /auto && \
    rm /tmp/mt5setup.exe

# Backup the pre-installed Wine prefix so it can be restored if /config is overridden by a host mount
RUN cp -a /config/.wine /opt/mt5-wine \
    && chown -R 1000:1002 /opt/mt5-wine

# Environment variables for MT5 startup
ENV MT5_CMD_OPTIONS="/config:/config/startup.ini"

# Expose ports
EXPOSE 3000 8001 8080

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD pgrep terminal64.exe || exit 1

# Use the base image's entrypoint
