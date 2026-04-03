pipeline {
  agent any

  options {
    timestamps()
    disableConcurrentBuilds()
  }

  parameters {
    booleanParam(name: 'DEPLOY_TO_K8S', defaultValue: true, description: 'Deploy to Kubernetes')
    booleanParam(name: 'RUN_TESTS', defaultValue: true, description: 'Run tests')
  }

  environment {
    SERVICE_A_PATH = 'services/service-a'
    SERVICE_B_PATH = 'services/service-b'
    ELASTIC_IP = '16.112.134.36'   // ✅ Added
  }

  stages {

    stage('Checkout') {
      steps { checkout scm }
    }

    stage('Preflight') {
      steps {
        sh '''
          set -eu
          command -v docker >/dev/null
          command -v kubectl >/dev/null
        '''
      }
    }

    stage('Detect Changes') {
      steps {
        script {
          def changes = sh(
            script: "git diff --name-only HEAD~1 HEAD || true",
            returnStdout: true
          ).trim()

          env.BUILD_A = changes.contains("service-a") ? "true" : "false"
          env.BUILD_B = changes.contains("service-b") ? "true" : "false"

          if (changes == "") {
            env.BUILD_A = "true"
            env.BUILD_B = "true"
          }
        }
      }
    }

    stage('Build & Push') {
      steps {
        withCredentials([usernamePassword(
          credentialsId: 'dockerhub-creds',
          usernameVariable: 'DH_USER',
          passwordVariable: 'DH_PASS'
        )]) {
          sh '''
            set -eu
            echo "$DH_PASS" | docker login -u "$DH_USER" --password-stdin

            if [ "$BUILD_A" = "true" ]; then
              docker build -t "$DH_USER/service-a:latest" "$SERVICE_A_PATH"
              docker push "$DH_USER/service-a:latest"
            fi

            if [ "$BUILD_B" = "true" ]; then
              docker build -t "$DH_USER/service-b:latest" "$SERVICE_B_PATH"
              docker push "$DH_USER/service-b:latest"
            fi
          '''
        }
      }
    }

    stage('Deploy') {
      when { expression { params.DEPLOY_TO_K8S } }
      steps {
        withCredentials([
          file(credentialsId: 'kubeconfig-mesh-demo', variable: 'KUBECONFIG_FILE')
        ]) {
          sh '''
            export KUBECONFIG="$KUBECONFIG_FILE"
            chmod +x scripts/deploy.sh
            ./scripts/deploy.sh charanseven
          '''
        }
      }
    }

    stage('Test') {
      when { expression { params.RUN_TESTS } }
      steps {
        withCredentials([
          file(credentialsId: 'kubeconfig-mesh-demo', variable: 'KUBECONFIG_FILE')
        ]) {
          sh '''
            export KUBECONFIG="$KUBECONFIG_FILE"
            export ELASTIC_IP=${ELASTIC_IP}
            chmod +x scripts/test.sh
            ./scripts/test.sh
          '''
        }
      }
    }
  }

  post {
    always { sh 'docker logout || true' }
  }
}