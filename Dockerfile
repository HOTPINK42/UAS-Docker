FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# ---------- Base packages ----------
RUN apt update && apt install -y \
    git meson ninja-build pkg-config gcc g++ \
    python3 python3-pip python3-setuptools python3-wheel \
    libglib2.0-dev libsystemd-dev \
    wget sudo supervisor network-manager dnsmasq

# Remove ModemManager (Rpanion conflict)
RUN apt purge -y modemmanager || true

# ---------- Build mavlink-router ----------
RUN git clone https://github.com/intel/mavlink-router.git
WORKDIR /mavlink-router
RUN git submodule update --init --recursive && \
    meson setup build && ninja -C build && ninja -C build install

# ---------- GStreamer + extras ----------
RUN apt update && apt install -y \
    gstreamer1.0-plugins-good gstreamer1.0-plugins-ugly \
    gstreamer1.0-plugins-bad gstreamer1.0-plugins-base-apps \
    libgstrtspserver-1.0-dev python3-gst-1.0 python3-netifaces \
    jq libxml2-dev libxslt1-dev python3-lxml python3-numpy \
    python3-future gpsbabel zip

# ---------- Install NodeJS 20 ----------
RUN apt install -y ca-certificates curl gnupg && mkdir -p /etc/apt/keyrings
RUN curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
      | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg
RUN echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_20.x nodistro main" \
      | tee /etc/apt/sources.list.d/nodesource.list
RUN apt update && apt install -y nodejs

# ---------- Install Rpanion Server ----------
WORKDIR /opt
RUN wget https://github.com/stephendade/Rpanion-server/releases/download/v0.11.4/rpanion-server_0.11.4_arm64.deb
RUN apt install -y ./rpanion-server_0.11.4_arm64.deb

# ---------- Fix Rpanion Python tool paths ----------
RUN PYDIR=$(find /usr/share/rpanion-server -type f -name gstcaps.py -printf '%h' | head -n 1) && \
    mkdir -p /opt/python && \
    chmod +x $PYDIR/*.py && \
    ln -sf $PYDIR/gstcaps.py /usr/bin/gstcaps.py && \
    ln -sf $PYDIR/wifi_scan.py /usr/bin/wifi_scan.py && \
    ln -sf $PYDIR/gstcaps.py /opt/python/gstcaps.py && \
    ln -sf $PYDIR/wifi_scan.py /opt/python/wifi_scan.py

# ---------- Supervisor configs ----------
RUN mkdir -p /etc/supervisor/conf.d

# mavlink-router service
RUN printf "[program:mavlink-router]\n\
command=/usr/bin/mavlink-routerd\n\
autostart=true\n\
autorestart=true\n\
stderr_logfile=/var/log/mavlink-router.err.log\n\
stdout_logfile=/var/log/mavlink-router.out.log\n" \
> /etc/supervisor/conf.d/mavlink-router.conf

# rpanion-server service
RUN printf "[program:rpanion]\n\
command=/usr/bin/node index.js\n\
directory=/usr/share/rpanion-server/app/server\n\
autostart=true\n\
autorestart=true\n\
stderr_logfile=/var/log/rpanion.err.log\n\
stdout_logfile=/var/log/rpanion.out.log\n" \
> /etc/supervisor/conf.d/rpanion.conf

CMD ["/usr/bin/supervisord", "-n"]
