{
  description = "Example: devenv tasks in derivations and CI";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    devenv.url = "github:cachix/devenv";
  };

  outputs = inputs@{ flake-parts, devenv, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [
        devenv.flakeModules.tasks # Import standalone task module
      ];

      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];

      perSystem = { config, pkgs, ... }: {
        # Define reusable tasks that can be used anywhere
        devenvTasks = {
          setup = {
            description = "Install project dependencies";
            exec = ''
              echo "📦 Installing dependencies..."
              [[ -f package.json ]] && npm install || echo "No package.json found"
              [[ -f requirements.txt ]] && pip install -r requirements.txt || echo "No requirements.txt found"
              echo "✅ Dependencies installed"
            '';
          };

          lint = {
            description = "Lint the codebase";
            exec = ''
              echo "🔍 Linting code..."
              echo "Checking shell scripts..."
              find . -name "*.sh" -exec shellcheck {} \; || echo "shellcheck not found"
              echo "✅ Linting complete"
            '';
            after = [ "setup" ];
          };

          build = {
            description = "Build the project";
            exec = ''
              echo "🔨 Building project..."
              mkdir -p dist
              echo "Built at $(date)" > dist/build-info.txt
              echo "✅ Build complete"
            '';
            after = [ "setup" ];
          };

          test = {
            description = "Run tests";
            exec = ''
              echo "🧪 Running tests..."
              echo "Test suite passed at $(date)"
              echo "✅ Tests complete"
            '';
            after = [ "build" ];
          };

          security-scan = {
            description = "Run security scans";
            exec = ''
              echo "🔒 Running security scans..."
              echo "No vulnerabilities found"
              echo "✅ Security scan complete"
            '';
            after = [ "build" ];
          };

          deploy-staging = {
            description = "Deploy to staging environment";
            exec = ''
              echo "🚀 Deploying to staging..."
              echo "Deployment target: staging"
              echo "✅ Deployed to staging"
            '';
            after = [ "test" "security-scan" "lint" ];
            environment = {
              DEPLOY_ENV = "staging";
              API_URL = "https://api.staging.example.com";
            };
          };

          deploy-prod = {
            description = "Deploy to production environment";
            exec = ''
              echo "🚀 Deploying to production..."
              echo "Deployment target: production"
              echo "✅ Deployed to production"
            '';
            after = [ "deploy-staging" ];
            environment = {
              DEPLOY_ENV = "production";
              API_URL = "https://api.example.com";
            };
          };
        };

        # Example: Using tasks in a derivation
        packages.my-app = pkgs.stdenv.mkDerivation {
          name = "my-app";
          src = pkgs.writeTextDir "app.txt" "Hello from my app!";

          buildPhase = ''
            echo "Using devenv tasks in derivation build..."

            # Run setup and build tasks
            ${config.packages.task-setup}/bin/task-setup
            ${config.packages.task-build}/bin/task-build

            # Copy source
            cp -r $src/* .
          '';

          checkPhase = ''
            echo "Running tests in derivation..."
            ${config.packages.task-test}/bin/task-test
          '';

          installPhase = ''
            mkdir -p $out/bin $out/share

            # Install our app
            echo '#!/bin/sh' > $out/bin/my-app
            echo 'echo "Hello from my-app!"' >> $out/bin/my-app
            echo 'cat ${config.packages.tasks-config}' >> $out/bin/my-app
            chmod +x $out/bin/my-app

            # Include build artifacts if they exist
            [[ -d dist ]] && cp -r dist/* $out/share/ || true
          '';

          doCheck = true;
        };

        # Example: CI/CD package that runs full pipeline
        packages.ci-pipeline = pkgs.writeShellScriptBin "ci-pipeline" ''
          set -e
          echo "🔄 Starting CI/CD pipeline..."

          # Use the task runner to execute the full dependency graph
          ${config.packages.tasks-runner}/bin/run-tasks deploy-staging

          echo "✅ CI/CD pipeline complete!"
        '';

        # Apps for easy access
        apps.ci = {
          type = "app";
          program = "${config.packages.ci-pipeline}/bin/ci-pipeline";
        };
      };
    };
}
