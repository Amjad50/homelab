FROM node:24-trixie AS node

FROM python:3.12-trixie

# Keep the terminal's Node 24 tooling without replacing Python 3.12.
COPY --from=node /usr/local/bin/node /usr/local/bin/node
COPY --from=node /usr/local/lib/node_modules /usr/local/lib/node_modules

RUN set -eux; \
    ln -s /usr/local/lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm; \
    ln -s /usr/local/lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx; \
    ln -s /usr/local/lib/node_modules/corepack/dist/corepack.js /usr/local/bin/corepack; \
    apt-get update; \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends jq procps; \
    rm -rf /var/lib/apt/lists/*; \
    pip install --no-cache-dir uv

WORKDIR /workspace
CMD ["/bin/bash"]
