FROM tailscale/tailscale:v1.98

RUN apk add --no-cache curl jq

COPY ts-adguard-entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
