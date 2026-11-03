# QUẨY BAR ONLINE — Godot dedicated server (headless)
# Build context: repository root
#   docker build -f multiplayer/Dockerfile -t qbo-game-server .

FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
  && apt-get install -y --no-install-recommends ca-certificates curl unzip fontconfig libfontconfig1 libfreetype6 \
  && rm -rf /var/lib/apt/lists/*

# Godot 4.7.2 headless-capable Linux binary (không cần export templates).
ARG GODOT_VERSION=4.7.2-stable
RUN mkdir -p /opt/godot \
  && curl -fsSL -o /tmp/godot.zip "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}/Godot_v${GODOT_VERSION}_linux.x86_64.zip" \
  && unzip -q /tmp/godot.zip -d /opt/godot \
  && rm /tmp/godot.zip \
  && chmod +x /opt/godot/Godot_v${GODOT_VERSION}_linux.x86_64 \
  && ln -s /opt/godot/Godot_v${GODOT_VERSION}_linux.x86_64 /usr/local/bin/godot

WORKDIR /app
COPY game ./game
COPY multiplayer/start.sh /app/start.sh
RUN chmod +x /app/start.sh

ENV QBO_GAME_PORT=7000
EXPOSE 7000/udp
CMD ["/app/start.sh"]
