# Образ-сборщик: тянет исходники эмулятора и компилирует их.
# Нужен, чтобы на хосте не требовались JDK/Ant/Maven — только Docker.
FROM eclipse-temurin:21-jdk-noble

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      git ant maven unzip zip bash ca-certificates \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /work
