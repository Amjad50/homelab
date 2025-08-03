FROM alpine:latest

RUN apk add --no-cache bash grep sed docker-cli

COPY adguard-configurator-entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
