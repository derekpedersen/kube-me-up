pipeline {
  agent any

  parameters {
    booleanParam(name: 'RUN_DEPLOY', defaultValue: false, description: 'Manually enable and approve deployment stages')
    choice(name: 'DEPLOY_STRATEGY', choices: ['make', 'install-script'], description: 'Deployment path when RUN_DEPLOY=true')
    string(name: 'DEPLOY_DOMAIN', defaultValue: 'alive.example.com', description: 'Ingress domain for install-script deploy')
    string(name: 'LETSENCRYPT_EMAIL', defaultValue: 'you@example.com', description: 'Email for install-script deploy')
  }

  options {
    skipDefaultCheckout true
  }

  environment {
    DOCKERHUB_CREDENTIALS_ID = 'docker-jenkins-pat'
    DOCKERHUB_URL = 'https://index.docker.io/v1/'
    DOKS_TOKEN_CREDENTIALS_ID = 'do-api-token'
    DOKS_CLUSTER_NAME = 'kube-me-up'
    ALIVE_REPO = 'derekpedersen/johnny-5-alive'
    DEBUG_REPO = 'derekpedersen/johnny-5-debug'
    DEPLOY_NAMESPACE = 'default'
  }

  stages {
    stage('Checkout') {
      steps {
        checkout scm
      }
    }

    stage('Build Images') {
      steps {
        sh 'make -C johnny-5-alive docker'
        sh 'make debug-build'
      }
    }

    stage('Push Images (main)') {
      when {
        branch 'main'
      }
      steps {
        withDockerRegistry([credentialsId: env.DOCKERHUB_CREDENTIALS_ID, url: env.DOCKERHUB_URL]) {
          sh 'make -C johnny-5-alive publish ALIVE_REPO=${ALIVE_REPO}'
          sh 'make debug-publish DEBUG_REPO=${DEBUG_REPO} DEBUG_TAG=${GIT_COMMIT}'
        }
      }
    }

    stage('Approve Main Deploy (main)') {
      when {
        allOf {
          branch 'main'
          expression { params.RUN_DEPLOY }
        }
      }
      input {
        message 'Approve deployment to main?'
        ok 'Approve deploy'
      }
      steps {
        echo 'Main deployment approved. Proceeding to selected deploy path.'
      }
    }

    stage('Deploy Alive + Debug (main)') {
      when {
        allOf {
          branch 'main'
          expression { params.RUN_DEPLOY }
          expression { params.DEPLOY_STRATEGY == 'make' }
        }
      }
      steps {
        withCredentials([string(credentialsId: env.DOKS_TOKEN_CREDENTIALS_ID, variable: 'DO_API_TOKEN')]) {
          sh '''#!/usr/bin/env bash
set -euo pipefail

make deploy-main \
  DOKS_CLUSTER_NAME="${DOKS_CLUSTER_NAME}" \
  ALIVE_REPO="${ALIVE_REPO}" \
  ALIVE_TAG="${GIT_COMMIT}" \
  DEBUG_REPO="${DEBUG_REPO}" \
  DEBUG_TAG="${GIT_COMMIT}" \
  DEBUG_NAMESPACE="${DEPLOY_NAMESPACE}" \
  DEBUG_POD_NAME=johnny-5-debug
'''
        }
      }
    }

    stage('Deploy via install.sh (main)') {
      when {
        allOf {
          branch 'main'
          expression { params.RUN_DEPLOY }
          expression { params.DEPLOY_STRATEGY == 'install-script' }
        }
      }
      steps {
        withCredentials([string(credentialsId: env.DOKS_TOKEN_CREDENTIALS_ID, variable: 'DO_API_TOKEN')]) {
          sh '''#!/usr/bin/env bash
set -euo pipefail

make doctl-auth \
  DOKS_CLUSTER_NAME="${DOKS_CLUSTER_NAME}" \
  DO_API_TOKEN="${DO_API_TOKEN}"

chmod +x ./install.sh
./install.sh \
  --use-existing-cluster \
  --deploy-mode kubernetes \
  --non-interactive \
  --yes \
  --domain "${DEPLOY_DOMAIN}" \
  --email "${LETSENCRYPT_EMAIL}" \
  --image-repository "${ALIVE_REPO}" \
  --image-tag "${GIT_COMMIT}" \
  --enable-hpa \
  --hpa-min-replicas 1 \
  --hpa-max-replicas 3 \
  --hpa-target-cpu 80 \
  --hpa-target-mem 80 \
  --with-debug-pod \
  --debug-pod-image "${DEBUG_REPO}:${GIT_COMMIT}" \
  --debug-pod-namespace "${DEPLOY_NAMESPACE}" \
  --debug-pod-name johnny-5-debug
'''
        }
      }
    }
  }

  post {
    always {
      echo "Branch: ${env.BRANCH_NAME}"
      echo "Image tag used: ${env.GIT_COMMIT}"
    }
    failure {
      echo 'Pipeline failed during build, publish, or deploy.'
    }
    success {
      echo 'Pipeline completed successfully.'
    }
  }
}
