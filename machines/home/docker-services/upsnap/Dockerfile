FROM ghcr.io/seriousm4x/upsnap:5

USER root

# Install libcap for setcap
RUN apk update && apk add --no-cache libcap

# Set capabilities on the upsnap binary
RUN setcap cap_net_raw=+ep ./upsnap

ARG USER_ID=1000
ARG GROUP_ID=1000

RUN addgroup -g ${GROUP_ID} -S upsnap && \
    adduser -S -D -u ${USER_ID} -G upsnap -h /home/upsnap upsnap && \
    mkdir -p /home/upsnap && \
    chown upsnap:upsnap /home/upsnap

USER upsnap
