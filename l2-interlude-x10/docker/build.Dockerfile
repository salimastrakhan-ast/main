# Образ-сборщик. Mobius Interlude компилируется с source/target 25,
# поэтому нужен именно JDK 25 — на 21 ant падает с "invalid source release".
FROM eclipse-temurin:25-jdk-noble

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      git ant unzip zip bash ca-certificates \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /work
