# Using devenv Tasks in Derivations and Other Nix Code

devenv tasks are now fully reusable outside of development shells! Here are the different ways you can use them:

## 1. Using Tasks from devenv Shells in Other Flakes

When you have a devenv shell with tasks defined, they are automatically exported as packages:

```nix
# In a flake that depends on your devenv project
{
  inputs = {
    my-devenv-project.url = "path:./path/to/devenv/project";
  };

  outputs = { nixpkgs, my-devenv-project, ... }: {
    packages.x86_64-linux = {
      # Run individual tasks
      run-build = my-devenv-project.packages.x86_64-linux.task-build;
      run-test = my-devenv-project.packages.x86_64-linux.task-test;

      # Use the full task runner with dependency resolution
      tasks-runner = my-devenv-project.packages.x86_64-linux.tasks-runner;

      # Access task configuration for custom usage
      tasks-config = my-devenv-project.packages.x86_64-linux.tasks-config;
    };
  };
}
```

## 2. Standalone Task Module (Recommended)

Use the dedicated task flakeModule for clean, reusable task definitions:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    devenv.url = "github:cachix/devenv";
  };

  outputs = inputs@{ flake-parts, devenv, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [
        devenv.flakeModules.tasks  # Import the standalone task module
      ];

      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];

      perSystem = { config, pkgs, ... }: {
        # Define reusable tasks
        devenvTasks = {
          build = {
            description = "Build the project";
            exec = ''
              echo "Building..."
              make build
            '';
            environment = {
              BUILD_ENV = "production";
            };
          };

          test = {
            description = "Run all tests";
            exec = ''
              echo "Running tests..."
              make test
            '';
            after = [ "build" ];  # Dependency resolution
          };

          lint = {
            description = "Lint the codebase";
            exec = "make lint";
            cwd = "./src";  # Run in specific directory
          };

          deploy = {
            description = "Deploy to staging";
            exec = "make deploy";
            after = [ "test" "lint" ];  # Multiple dependencies
            environment = {
              DEPLOY_TARGET = "staging";
            };
          };
        };

        # Tasks are automatically exported as packages and apps
      };
    };
}
```

## 3. Using Tasks in CI/CD

### GitHub Actions Example

```yaml
name: CI
on: [push, pull_request]

jobs:
  build-and-test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: DeterminateSystems/nix-installer-action@v4
      - uses: DeterminateSystems/magic-nix-cache-action@v2

      # Run individual tasks
      - name: Build
        run: nix run .#task-build

      - name: Test
        run: nix run .#task-test

      # Or use the task runner with dependency resolution
      - name: Run all tasks
        run: nix run .#tasks deploy  # Runs build → test & lint → deploy
```

### Using in Derivations

```nix
{
  inputs = {
    my-tasks.url = "path:./my-tasks-flake";
  };

  outputs = { nixpkgs, my-tasks, ... }:
    let
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
    in {
      packages.x86_64-linux.my-app = pkgs.stdenv.mkDerivation {
        name = "my-app";
        src = ./.;

        buildPhase = ''
          # Use devenv tasks in the build process
          ${my-tasks.packages.x86_64-linux.task-build}/bin/task-build
        '';

        checkPhase = ''
          # Run tests as part of the derivation
          ${my-tasks.packages.x86_64-linux.task-test}/bin/task-test
        '';

        installPhase = ''
          # Tasks can be part of install too
          mkdir -p $out/bin
          cp result/* $out/bin/
        '';
      };
    };
}
```

## 4. Advanced Usage: Task Composition

```nix
perSystem = { config, pkgs, ... }: {
  devenvTasks = {
    # Base tasks
    setup = {
      description = "Setup dependencies";
      exec = "npm install";
    };

    lint-js = {
      description = "Lint JavaScript";
      exec = "eslint src/";
      after = [ "setup" ];
    };

    lint-css = {
      description = "Lint CSS";
      exec = "stylelint styles/";
      after = [ "setup" ];
    };

    test-unit = {
      description = "Run unit tests";
      exec = "npm run test:unit";
      after = [ "setup" ];
    };

    test-integration = {
      description = "Run integration tests";
      exec = "npm run test:integration";
      after = [ "test-unit" ];
    };

    # Composite tasks
    lint = {
      description = "Run all linting";
      exec = "echo 'All linting complete'";
      after = [ "lint-js" "lint-css" ];
    };

    test = {
      description = "Run all tests";
      exec = "echo 'All tests complete'";
      after = [ "test-integration" ];
    };

    ci = {
      description = "Full CI pipeline";
      exec = "echo 'CI pipeline complete'";
      after = [ "lint" "test" ];
    };
  };
};
```

## 5. Available Interfaces

### Packages
- `task-<name>` - Individual task executables
- `tasks-runner` - Task runner with dependency resolution
- `tasks-config` - JSON configuration file for custom integrations

### Apps (via `nix run`)
- `nix run .#task-<name>` - Run individual task
- `nix run .#tasks <name>` - Run task with dependencies
- `nix run .#tasks` - List all available tasks

### Command Examples
```bash
# List available tasks
nix run .#tasks

# Run a specific task
nix run .#tasks build

# Run task with dependencies (will run build → test → deploy)
nix run .#tasks deploy

# Run individual task directly
nix run .#task-lint

# Use in shell scripts
$(nix build .#task-build --print-out-paths)/bin/task-build

# Access task configuration
nix eval .#tasks-config --json | jq
```

This makes devenv tasks completely portable and reusable across your entire Nix ecosystem!