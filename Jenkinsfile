pipeline {
  agent any

  environment {
    SERVICE_A_PATH = 'services/service-a'
    SERVICE_B_PATH = 'services/service-b'
    ELASTIC_IP = '16.112.134.36'
  }

  stages {

    stage('Checkout') {
      steps { checkout scm }
    }

    stage('Build & Push') {
      steps {
        withCredentials([usernamePassword(
          credentialsId: 'dockerhub-creds',
          usernameVariable: 'DH_USER',
          passwordVariable: 'DH_PASS'
        )]) {
          sh '''
            echo "$DH_PASS" | docker login -u "$DH_USER" --password-stdin

            docker build -t "$DH_USER/service-a:latest" "$SERVICE_A_PATH"
            docker push "$DH_USER/service-a:latest"

            docker build -t "$DH_USER/service-b:latest" "$SERVICE_B_PATH"
            docker push "$DH_USER/service-b:latest"
          '''
        }
      }
    }

    stage('Deploy') {
      steps {
        withCredentials([
          file(credentialsId: 'kubeconfig-mesh-demo', variable: 'KUBECONFIG_FILE')
        ]) {
          sh '''
            export KUBECONFIG="$KUBECONFIG_FILE"
            kubectl apply -f k8s/
          '''
        }
      }
    }

    stage('Test') {
      steps {
        withCredentials([
          file(credentialsId: 'kubeconfig-mesh-demo', variable: 'KUBECONFIG_FILE')
        ]) {
          sh '''
            export KUBECONFIG="$KUBECONFIG_FILE"
            chmod +x scripts/test.sh
            ./scripts/test.sh
          '''
        }
      }
    }
  }
}