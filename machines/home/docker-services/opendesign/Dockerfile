FROM ghcr.io/nexu-io/od:latest

USER root

# Keep Codex in the same image as OpenDesign; no host CLI or home mount.
RUN npm install -g @openai/codex@latest \
    && codex --version \
    && mkdir -p /home/open-design/.codex \
    && chown -R 1001:1001 /home/open-design

ENV HOME=/home/open-design \
    CODEX_HOME=/home/open-design/.codex

USER open-design
