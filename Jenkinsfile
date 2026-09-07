pipeline {
  agent any

  options {
    skipDefaultCheckout true
    timestamps()
  }

  environment {
    DOCKERHUB_CREDENTIALS_ID = 'docker-jenkins-pat'
    DOCKERHUB_URL = 'https://index.docker.io/v1/'
    ALIVE_REPO = 'derekpedersen/johnny-5-alive'
    DEBUG_REPO = 'derekpedersen/johnny-5-debug'
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

    stage('Push Images') {
      steps {
        withDockerRegistry([credentialsId: env.DOCKERHUB_CREDENTIALS_ID, url: env.DOCKERHUB_URL]) {
          sh 'make -C johnny-5-alive publish ALIVE_REPO=${ALIVE_REPO}'
          sh 'make debug-publish DEBUG_REPO=${DEBUG_REPO}'
        }
      }
    }
  }
}
