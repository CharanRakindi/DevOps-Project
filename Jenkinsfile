pipeline {
  agent any

  environment {
    SERVICE_A_PATH = 'services/service-a'
    SERVICE_B_PATH = 'services/service-b'
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
          file(credentialsId: 'kubeconfig-mesh-demo', variable: 'KUBECONFIG_FILE'),
          usernamePassword(
            credentialsId: 'dockerhub-creds',
            usernameVariable: 'DH_USER',
            passwordVariable: 'DH_PASS'
          )
        ]) {
          sh '''
            export KUBECONFIG="$KUBECONFIG_FILE"
            chmod +x scripts/deploy.sh
            ./scripts/deploy.sh $DH_USER
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