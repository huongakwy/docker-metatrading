# Dockerfile for MetaTrader 5 Docker Cluster
# Base image with MT5 and VNC pre-installed

FROM gmag11/metatrader5_vnc:1.0

# Maintainer information
LABEL maintainer="MT5 Docker Team"
LABEL description="MetaTrader 5 with automated EA attachment"

# Download MT5 installer
ADD https://download.mql5.com/cdn/web/metaquotes/software/mt5/mt5setup.exe /tmp/mt5setup.exe

# Create user with correct UID/GID (1000:1002) instead of default 911
RUN (groupdel abc 2>/dev/null || true) && \
    (groupmod -g 1002 kasm-user 2>/dev/null || groupadd -g 1002 kasm-user) && \
    (usermod -u 1000 -g 1002 kasm-user 2>/dev/null || useradd -u 1000 -g 1002 -G audio,video -m -s /bin/bash kasm-user)

# Setup Wine prefix and install MetaTrader 5 silently using a virtual framebuffer
RUN apk add --no-cache xvfb && \
    Xvfb :99 -ac -screen 0 1024x768x16 & \
    PID=$! && \
    sleep 2 && \
    DISPLAY=:99 WINEPREFIX=/config/.wine wineboot --init && \
    DISPLAY=:99 WINEPREFIX=/config/.wine wine /tmp/mt5setup.exe /auto || true && \
    kill $PID && \
    rm /tmp/mt5setup.exe && \
    apk del xvfb

# Backup the pre-installed Wine prefix so it can be restored if /config is overridden by a host mount
RUN cp -a /config/.wine /opt/mt5-wine \
    && chown -R 1000:1002 /opt/mt5-wine

# Copy MQL5 folders and templates to base template directory
RUN mkdir -p /opt/mt5-base-terminal
COPY MQL5/ /opt/mt5-base-terminal/MQL5/
COPY snapshot/Terminal/ /opt/mt5-base-terminal/Terminal/
COPY snapshot/Config/ /opt/mt5-base-terminal/Config/
COPY snapshot/Profiles/ /opt/mt5-base-terminal/Profiles/
COPY snapshot/profiles/ /opt/mt5-base-terminal/profiles/
RUN chown -R 1000:1002 /opt/mt5-base-terminal \
    && find /opt/mt5-base-terminal -type d -exec chmod 755 {} \; \
    && find /opt/mt5-base-terminal -type f -exec chmod 644 {} \;

# Copy custom start.sh to /Metatrader/ (overwrites base start.sh)
COPY scripts/profile-snapshot-automation/start.sh /Metatrader/start.sh
RUN chmod +x /Metatrader/start.sh \
    && chown 1000:1002 /Metatrader/start.sh

# Environment variables for MT5 startup
ENV MT5_CMD_OPTIONS="/config:/config/startup.ini"

# Expose ports
EXPOSE 3000 8001 8080

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD pgrep terminal64.exe || exit 1

# Use the base image's entrypoint
