#!/bin/bash
set -euo pipefail

## 引数をチェックする
if [ ! $# = 1 ]; then
  echo "Usage: sh init-nodejs-nextjs.sh {project name}"
  exit 1
fi
PROJECT_NAME="${1}"

## 1. 引数を使ってプロジェクトのフォルダをつくる
## ------------------------------------------------------------
[ ! -e "${PROJECT_NAME}" ] \
    && mkdir "${PROJECT_NAME}" \
    && cd "${PROJECT_NAME}"

## 2. docker-compose.yaml を生成する
## ------------------------------------------------------------
cat <<DOCKER-COMPOSE >docker-compose.yaml
version: '3'
services:
  # ----------------------------------------
  # Application
  # ----------------------------------------
  ${PROJECT_NAME}_app:
    container_name: ${PROJECT_NAME}_app
    build:
      context: app
    command: sh -c "npm i && npm update && npm run build && npm run start"
    environment:
      - TZ=Asia/Tokyo
    volumes:
      - ./app/src:/work
    ports:
      - 3000:3000
  # ----------------------------------------
  # Reverse proxy
  # ----------------------------------------
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

function addJenkins() {
## (注意)
## CICD パイプライン部分の構築はまだ正常に動作していないので、関数で隔離しています。
## 正常に動作するようになったら、

cat <<DOCKER-COMPOSE >>docker-compose.yaml
  # ----------------------------------------
  # CI/CD pipeline
  # Jenkins Configuration as Code (JCasC)
  # ----------------------------------------
  ${PROJECT_NAME}_ci_jenkins:
    container_name: ${PROJECT_NAME}_ci_jenkins
    build:
      context: ./cicd/jenkins
      dockerfile: Dockerfile
    restart: always
    environment:
      JENKINS_ADMIN_ID: admin
      JENKINS_ADMIN_PASSWORD: Admin@000
    volumes:
      - ./cicd/jenkins/seedjobs:/var/jenkins_home/seedjobs
      #- ./cicd/jenkins/data:/var/jenkins_home # DEBUG
    ports:
      - 8001:8080
    links:
      - ${PROJECT_NAME}_ci_jenkins_agent
  ${PROJECT_NAME}_ci_jenkins_agent:
    container_name: ${PROJECT_NAME}_ci_jenkins_agent
    image: jenkinsci/ssh-slave
    environment:
      JENKINS_SLAVE_SSH_PUBKEY:
DOCKER-COMPOSE

## 3. CICDパイプラインを構築する
## ------------------------------------------------------------
[ ! -e cicd/jenkins ] \
    && mkdir -p cicd/jenkins/seedJobs

## 3-1. Dockerfile
cat <<DOCKERFILE >cicd/jenkins/Dockerfile
FROM jenkins/jenkins:lts-jdk11
ENV JAVA_OPTS -Djenkins.install.runSetupWizard=false
# install plugins
COPY plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt
# set a jenkins url and some configuration of the plugins above
ENV CASC_JENKINS_CONFIG /var/jenkins_home/jenkins_casc.yaml
COPY jenkins_casc.yaml /usr/share/jenkins/ref/jenkins_casc.yaml
DOCKERFILE

## 3-2. JCasC file
cat <<JCASC >cicd/jenkins/jenkins_casc.yaml
jenkins:
  numExecutors: 1
  remotingSecurity:
    enabled: true
  authorizationStrategy:
    globalMatrix:
      permissions:
        - "Overall/Administer:admin"
        - "Overall/Read:authenticated"
  securityRealm:
    local:
      allowsSignup: false
      users:
       - id: \${JENKINS_ADMIN_ID}
         password: \${JENKINS_ADMIN_PASSWORD}
  nodes:
    - permanent:
        name: "static-agent"
        remoteFS: "/home/jenkins"
        launcher:
          jnlp:
            workDirSettings:
              disabled: true
              failIfWorkDirIsMissing: false
              internalDir: "remoting"
              workDirPath: "/tmp"
  slaveAgentPort: 50000
  agentProtocols:
    - "jnlp2"
tool:
  git:
    installations:
      - name: git
        home: /usr/local/bin/git
security:
  queueItemAuthenticator:
    authenticators:
    - global:
        strategy: triggeringUsersAuthorizationStrategy
unclassified:
  location:
    url: http://localhost:8001/
jobs:
  - file: /var/jenkins_home/seedjobs/pipeline_seed_job.groovy
JCASC

## 3-3. Plugins list file
cat <<PLUGINS >cicd/jenkins/plugins.txt
ant:latest
antisamy-markup-formatter:latest
authorize-project:latest
build-timeout:latest
cloudbees-folder:latest
configuration-as-code:latest
credentials-binding:latest
docker-plugin:latest
docker-workflow:latest
email-ext:latest
git:latest
github-branch-source:latest
gradle:latest
job-dsl:latest
ldap:latest
mailer:latest
matrix-auth:latest
pam-auth:latest
pipeline-github-lib:latest
pipeline-stage-view:latest
ssh-slaves:latest
timestamper:latest
workflow-aggregator:latest
ws-cleanup:latest
PLUGINS

## 3-4. Seed jobs
cat <<JOB >cicd/jenkins/seedJobs/pipeline_seed_job.groovy
title = "CI/CD Pipeline seed"
appName = "${PROJECT_NAME}"
repository = '{repository owner}/{repository name}'
pipelineJob(title) {
  description('This is a job template in your local jenkins server. Edit scripts to check your code of \${appName}.')
  definition {
    cpsScm {
      scm {
        git{
          remote{
            url('https://github.com/'+repository)
          }
          branch('*/develop')
        }
        scriptPath('Jenkinsfile')
      }
    }
  }
}
JOB
}

##  4. app フォルダにDockerfile を生成する
## ------------------------------------------------------------
[ ! -e app ] \
    && mkdir app

cat <<DOCKERFILE >app/Dockerfile
FROM node:latest
WORKDIR /work
DOCKERFILE

## 5. 実行環境にプロジェクトのソースコードを展開する
## ------------------------------------------------------------
[ ! -e app/src ] \
    && git clone https://github.com/nextauthjs/next-auth-example.git app/src \
    && cd app/src \
    && npm install next-pwa

## 6. 実行環境でアプリを起動する
## ------------------------------------------------------------
docker-compose up -d && docker logs "${PROJECT_NAME}"_app -f
