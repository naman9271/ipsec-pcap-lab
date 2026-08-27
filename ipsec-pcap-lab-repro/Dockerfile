FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       strongswan \
       iproute2 \
       iputils-ping \
       curl \
       python3 \
       ffmpeg \
       procps \
       ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY docker/entrypoint.sh /usr/local/bin/ipsec-lab-entrypoint
RUN chmod +x /usr/local/bin/ipsec-lab-entrypoint

ENTRYPOINT ["/usr/local/bin/ipsec-lab-entrypoint"]
CMD ["sleep", "infinity"]
