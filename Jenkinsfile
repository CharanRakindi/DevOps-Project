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

    // ✅ 1. Checkout (ONLY ONCE)
    stage('Checkout') {
      steps {
        checkout scm
      }
    }

    // ✅ 2. Pre-checks
    stage('Preflight') {
      steps {
        sh '''
          set -eu
          command -v docker >/dev/null
          command -v kubectl >/dev/null
          test -f scripts/deploy.sh
          test -f scripts/test.sh
          test -f k8s/02-deployments.yaml
        '''
      }
    }

    // ✅ 3. Detect changes (SMART BUILD)
    stage('Detect Changes') {
      steps {
        script {
          def changes = sh(
            script: "git diff --name-only HEAD~1 HEAD || true",
            returnStdout: true
          ).trim()

          echo "Changed files: ${changes}"

          env.BUILD_A = changes.contains("services/service-a") ? "true" : "false"
          env.BUILD_B = changes.contains("services/service-b") ? "true" : "false"

          // First build case (no previous commit)
          if (changes == "") {
            env.BUILD_A = "true"
            env.BUILD_B = "true"
          }

          echo "Build Service A: ${env.BUILD_A}"
          echo "Build Service B: ${env.BUILD_B}"
        }
      }
    }

    // ✅ 4. Build & Push (ONLY IF CHANGED)
    stage('Build and Push Images') {
      steps {
        withCredentials([
          usernamePassword(
            credentialsId: 'dockerhub-creds',
            usernameVariable: 'DH_USER',
            passwordVariable: 'DH_PASS'
          )
        ]) {
          sh '''
            set -eu

            echo "$DH_PASS" | docker login -u "$DH_USER" --password-stdin

            # ---------- SERVICE A ----------
            if [ "$BUILD_A" = "true" ]; then
              echo "🚀 Building Service A..."

              docker build --build-arg APP_VERSION=v1 \
                -t "$DH_USER/service-a:v1" \
                -t "$DH_USER/service-a:latest" \
                "$SERVICE_A_PATH"

              docker build --build-arg APP_VERSION=v2 \
                -t "$DH_USER/service-a:v2" \
                "$SERVICE_A_PATH"

              docker push "$DH_USER/service-a:v1"
              docker push "$DH_USER/service-a:v2"
              docker push "$DH_USER/service-a:latest"
            else
              echo "⏭️ Skipping Service A (no changes)"
            fi

            # ---------- SERVICE B ----------
            if [ "$BUILD_B" = "true" ]; then
              echo "🚀 Building Service B..."

              docker build --build-arg APP_VERSION=v1 \
                -t "$DH_USER/service-b:v1" \
                -t "$DH_USER/service-b:latest" \
                "$SERVICE_B_PATH"

              docker push "$DH_USER/service-b:v1"
              docker push "$DH_USER/service-b:latest"
            else
              echo "⏭️ Skipping Service B (no changes)"
            fi
          '''
        }
      }
    }

    // ✅ 5. Deploy
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
            set -eu
            export KUBECONFIG="$KUBECONFIG_FILE"

            chmod +x scripts/deploy.sh
            ./scripts/deploy.sh "$DH_USER"
          '''
        }
      }
    }

    // ✅ 6. Tests
    stage('Run Mesh Tests') {
      when {
        allOf {
          expression { params.DEPLOY_TO_K8S }
          expression { params.RUN_TESTS }
        }
      }
      steps {
        withCredentials([
          file(credentialsId: 'kubeconfig-mesh-demo', variable: 'KUBECONFIG_FILE')
        ]) {
          sh '''
            set -eu
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
      echo '✅ Pipeline completed successfully.'
    }
    failure {
      echo '❌ Pipeline failed. Check logs.'
    }
  }
}