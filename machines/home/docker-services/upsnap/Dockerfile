FROM ghcr.io/seriousm4x/upsnap:5

USER root

# Install libcap for setcap
RUN apk update && apk add --no-cache libcap

# Set capabilities on the upsnap binary
RUN setcap cap_net_raw=+ep ./upsnap