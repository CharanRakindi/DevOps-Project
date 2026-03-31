pipeline {
  agent any

  options {
    timestamps()
    disableConcurrentBuilds()
  }

  parameters {
    booleanParam(name: 'DEPLOY_TO_K8S', defaultValue: true, description: 'Deploy to Kubernetes after pushing Docker images')
    booleanParam(name: 'RUN_TESTS', defaultValue: true, description: 'Run mesh verification tests after deployment')
  }

  environment {
    SERVICE_A_PATH = 'services/service-a'
    SERVICE_B_PATH = 'services/service-b'
  }

  stages {
    stage('Checkout') {
      steps {
        checkout scm
      }
    }

    stage('Preflight') {
      steps {
        sh '''
          set -euo pipefail
          command -v docker >/dev/null
          command -v kubectl >/dev/null
          test -f scripts/deploy.sh
          test -f scripts/test.sh
          test -f k8s/02-deployments.yaml
        '''
      }
    }

    stage('Build and Push Images') {
      steps {
        withCredentials([usernamePassword(credentialsId: 'dockerhub-creds', usernameVariable: 'DH_USER', passwordVariable: 'DH_PASS')]) {
          sh '''
            set -euo pipefail

            echo "$DH_PASS" | docker login -u "$DH_USER" --password-stdin

            docker build --build-arg APP_VERSION=v1 -t "$DH_USER/service-a:v1" -t "$DH_USER/service-a:latest" "$SERVICE_A_PATH"
            docker build --build-arg APP_VERSION=v2 -t "$DH_USER/service-a:v2" "$SERVICE_A_PATH"
            docker build --build-arg APP_VERSION=v1 -t "$DH_USER/service-b:v1" -t "$DH_USER/service-b:latest" "$SERVICE_B_PATH"

            docker push "$DH_USER/service-a:v1"
            docker push "$DH_USER/service-a:v2"
            docker push "$DH_USER/service-a:latest"
            docker push "$DH_USER/service-b:v1"
            docker push "$DH_USER/service-b:latest"
          '''
        }
      }
    }

    stage('Deploy to Kubernetes') {
      when {
        expression { params.DEPLOY_TO_K8S }
      }
      steps {
        withCredentials([
          usernamePassword(credentialsId: 'dockerhub-creds', usernameVariable: 'DH_USER', passwordVariable: 'DH_PASS'),
          file(credentialsId: 'kubeconfig-mesh-demo', variable: 'KUBECONFIG_FILE')
        ]) {
          sh '''
            set -euo pipefail
            export KUBECONFIG="$KUBECONFIG_FILE"

            chmod +x scripts/deploy.sh
            ./scripts/deploy.sh "$DH_USER"
          '''
        }
      }
    }

    stage('Run Mesh Tests') {
      when {
        allOf {
          expression { params.DEPLOY_TO_K8S }
          expression { params.RUN_TESTS }
        }
      }
      steps {
        withCredentials([file(credentialsId: 'kubeconfig-mesh-demo', variable: 'KUBECONFIG_FILE')]) {
          sh '''
            set -euo pipefail
            export KUBECONFIG="$KUBECONFIG_FILE"

            chmod +x scripts/test.sh
            ./scripts/test.sh
          '''
        }
      }
    }
  }

  post {
    always {
      sh 'docker logout || true'
    }
    success {
      echo 'Pipeline completed successfully.'
    }
    failure {
      echo 'Pipeline failed. Check stage logs for details.'
    }
  }
}
