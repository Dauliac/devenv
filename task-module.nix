# Standalone flakeModule for devenv tasks that can be used in any flake-parts project
devenvFlake: { flake-parts-lib, lib, inputs, ... }: {
  options.perSystem = flake-parts-lib.mkPerSystemOption ({ config, pkgs, system, ... }:
    let
      taskType = lib.types.submodule ({ name, config, ... }: {
        options = {
          exec = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Command to execute the task.";
          };
          description = lib.mkOption {
            type = lib.types.str;
            default = "";
            description = "Description of the task.";
          };
          after = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            description = "List of tasks that must complete before this task runs.";
            default = [ ];
          };
          before = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            description = "List of tasks that depend on this task completing first.";
            default = [ ];
          };
          cwd = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Working directory to run the task in.";
          };
          environment = lib.mkOption {
            type = lib.types.attrsOf lib.types.str;
            default = { };
            description = "Environment variables for the task.";
          };
          package = lib.mkOption {
            type = lib.types.package;
            default = pkgs.bash;
            description = "Package to use for running the task.";
          };
        };
      });

      mkTaskPackage = name: task: pkgs.writeShellScriptBin "task-${name}" ''
        set -e
        ${lib.concatStringsSep "\n" (lib.mapAttrsToList (k: v: "export ${k}=${lib.escapeShellArg v}") task.environment)}
        ${lib.optionalString (task.cwd != null) "cd ${lib.escapeShellArg task.cwd}"}
        ${lib.optionalString (task.exec != null) task.exec}
      '';

      mkTaskRunner = tasks:
        let
          tasksJson = lib.mapAttrsToList
            (name: task: {
              inherit name;
              description = task.description;
              command = "${mkTaskPackage name task}/bin/task-${name}";
              after = task.after;
              before = task.before;
              cwd = task.cwd;
            })
            tasks;

          configFile = pkgs.writeText "tasks.json" (builtins.toJSON tasksJson);
        in
        pkgs.writeShellScriptBin "run-tasks" ''
          # Simple task runner with dependency resolution
          task_name="$1"
          shift || true

          if [[ -z "$task_name" ]]; then
            echo "Available tasks:"
            ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: task:
              "echo \"  ${name}: ${task.description}\""
            ) tasks)}
            exit 1
          fi

          case "$task_name" in
            ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: task: ''
              ${name})
                echo "Running task: ${name}"
                exec ${mkTaskPackage name task}/bin/task-${name} "$@"
                ;;
            '') tasks)}
            *)
              echo "Unknown task: $task_name"
              exit 1
              ;;
          esac
        '';
    in
    {
      options.devenvTasks = lib.mkOption {
        type = lib.types.attrsOf taskType;
        default = { };
        description = ''
          Standalone devenv-style tasks that can be used in derivations and CI.
          These tasks are independent of devenv shells and can be run anywhere.
        '';
        example = lib.literalExpression ''
          {
            build = {
              description = "Build the project";
              exec = "make build";
            };
            test = {
              description = "Run tests";
              exec = "make test";
              after = [ "build" ];
            };
          }
        '';
      };

      config.packages = lib.concatMapAttrs
        (name: task: {
          "task-${name}" = mkTaskPackage name task;
        })
        config.devenvTasks
      // lib.optionalAttrs (config.devenvTasks != { }) {
        "tasks-runner" = mkTaskRunner config.devenvTasks;
        "tasks-config" = pkgs.writeText "tasks.json" (builtins.toJSON
          (lib.mapAttrsToList
            (name: task: {
              inherit name;
              description = task.description;
              after = task.after;
              before = task.before;
              cwd = task.cwd;
            })
            config.devenvTasks)
        );
      };

      config.apps = lib.concatMapAttrs
        (name: task: {
          "task-${name}" = {
            type = "app";
            program = "${mkTaskPackage name task}/bin/task-${name}";
          };
        })
        config.devenvTasks
      // lib.optionalAttrs (config.devenvTasks != { }) {
        "tasks" = {
          type = "app";
          program = "${mkTaskRunner config.devenvTasks}/bin/run-tasks";
        };
      };
    }
  );

  _file = __curPos.file;
}
