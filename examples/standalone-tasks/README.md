# Standalone devenv Tasks Example

This example demonstrates how to use devenv tasks in derivations, CI/CD, and other Nix code outside of development shells.

## Quick Start

```bash
# List all available tasks
nix run .#tasks

# Run individual tasks
nix run .#tasks setup
nix run .#tasks build
nix run .#tasks test

# Run tasks with full dependency resolution
nix run .#tasks deploy-staging  # Runs: setup → build & lint → test & security-scan → deploy-staging

# Run the complete CI pipeline
nix run .#ci

# Build the example app (uses tasks in derivation)
nix build .#my-app

# Run the built app
./result/bin/my-app
```

## Available Tasks

- **setup** - Install project dependencies
- **lint** - Lint the codebase (depends on setup)
- **build** - Build the project (depends on setup)
- **test** - Run tests (depends on build)
- **security-scan** - Run security scans (depends on build)
- **deploy-staging** - Deploy to staging (depends on test, security-scan, lint)
- **deploy-prod** - Deploy to production (depends on deploy-staging)

## Task Features Demonstrated

### 1. Dependency Resolution
Tasks automatically run their dependencies in the correct order:
```bash
nix run .#tasks deploy-staging
# Automatically runs: setup → build & lint → test & security-scan → deploy-staging
```

### 2. Environment Variables
Tasks can set environment variables:
```bash
nix run .#tasks deploy-staging  # Sets DEPLOY_ENV=staging
nix run .#tasks deploy-prod     # Sets DEPLOY_ENV=production
```

### 3. Working Directory
Tasks can specify their working directory (see lint task example).

### 4. Integration with Derivations
The `my-app` package demonstrates using tasks within Nix derivations for build and test phases.

### 5. CI/CD Integration
The `ci-pipeline` package shows how to create automated pipelines using tasks.

## Using in Your Projects

### 1. Import the Task Module
```nix
{
  inputs = {
    devenv.url = "github:cachix/devenv";
    flake-parts.url = "github:hercules-ci/flake-parts";
  };

  outputs = inputs@{ flake-parts, devenv, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [
        devenv.flakeModules.tasks  # ← Add this
      ];
      # ...
    };
}
```

### 2. Define Your Tasks
```nix
perSystem = { ... }: {
  devenvTasks = {
    my-task = {
      description = "My custom task";
      exec = "echo 'Hello, World!'";
    };
  };
};
```

### 3. Use Anywhere
```bash
# Command line
nix run .#tasks my-task

# In derivations
${config.packages.task-my-task}/bin/task-my-task

# In CI/CD
nix run .#tasks my-task
```

## GitHub Actions Example

```yaml
name: CI
on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: DeterminateSystems/nix-installer-action@v4
      - name: Run full CI pipeline
        run: nix run .#tasks deploy-staging
```

This approach makes your build and deployment logic:
- ✅ **Reproducible** - Same results everywhere
- ✅ **Reusable** - Use in shells, derivations, CI/CD
- ✅ **Composable** - Tasks depend on each other automatically
- ✅ **Fast** - Nix caching and parallel execution
- ✅ **Portable** - Works on any system with Nix