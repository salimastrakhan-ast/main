# Рантайм для LoginServer и GameServer.
# JRE 21 — на нём Mobius работает штатно, и именно там доступен
# generational ZGC (паузы GC < 1 мс, для игрового сервера это ключевое).
FROM eclipse-temurin:21-jre-noble

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      bash tini mariadb-client tzdata ca-certificates procps \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/l2/server

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# tini как PID 1: корректно доставляет SIGTERM в JVM, иначе при
# `docker compose stop` сервер убивается по таймауту и персонажи
# сохраняются не полностью.
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
CMD ["game"]
