#!/bin/bash
set -euo pipefail

## 引数をチェックする
if [ ! $# = 1 ]; then
  echo "Usage: sh init-nodejs-nextjs.sh {project name}"
  exit 1
fi
PROJECT_NAME="${1}"

## 1. 引数を使ってプロジェクトのフォルダをつくる
[ ! -e "${PROJECT_NAME}" ] \
    && mkdir "${PROJECT_NAME}"

## 2. docker-compose.yaml を生成する
cd "${PROJECT_NAME}"
cat <<DOCKER-COMPOSE >docker-compose.yaml
version: '3'
services:
  ${PROJECT_NAME}_app:
    container_name: ${PROJECT_NAME}_app
    build:
      context: app
    command: sh -c "npm i && npm update && npm run build && npm run start"
    environment:
      - TZ=Asia/Tokyo
    volumes:
      - ./app/${PROJECT_NAME}:/work
    ports:
      - 3000:3000
  ${PROJECT_NAME}_https:
    container_name: ${PROJECT_NAME}_https
    image: steveltn/https-portal:latest
    links:
      - ${PROJECT_NAME}_app
    environment:
      DOMAINS: localhost -> http://${PROJECT_NAME}_app:3000
      STAGE: "local" # STAGE: 'production' # Don't use production until staging works. STAGE is 'staging' by default.
      # FORCE_RENEW: 'true'
      ERROR_LOG: stdout
      ACCESS_LOG: stderr
    volumes:
      - ./certs:/var/lib/https-portal
    ports:
      - 80:80
      - 443:443
    restart: always
DOCKER-COMPOSE

## 3. app フォルダをつくる
[ ! -e app ] \
    && mkdir app

## 4. app フォルダにDockerfile を生成する
cat <<DOCKERFILE >app/Dockerfile
FROM node:latest
WORKDIR /work
DOCKERFILE

## 5. 実行環境にプロジェクトのソースコードを展開する
[ ! -e app/"${PROJECT_NAME}" ] \
    && git clone https://github.com/nextauthjs/next-auth-example.git app/"${PROJECT_NAME}" \
    && cd app/"${PROJECT_NAME}" \
    && npm install next-pwa

## 6. 実行環境でアプリを起動する
docker-compose up -d && docker logs "${PROJECT_NAME}"_app -f
