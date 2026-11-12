ARG image=lavasoftware/lava-dispatcher:latest
FROM ${image}

RUN apt-get -q update \
 && DEBIAN_FRONTEND=noninteractive apt-get -q -y install --no-install-recommends \
    openssh-client telnet expect \
 && rm -rf /var/lib/apt/lists/*
