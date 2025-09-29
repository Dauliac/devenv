devenvFlake: { flake-parts-lib, lib, inputs, ... }: {
  options.perSystem = flake-parts-lib.mkPerSystemOption ({ config, pkgs, system, ... }:

    let
      devenvType = (devenvFlake.lib.mkEval {
        inherit inputs pkgs;
        modules = [
          ({ config, ... }: {
            config = {
              _module.args.pkgs = pkgs.appendOverlays config.overlays;
              # Add flake-parts-specific config here if necessary
            };
          })
        ] ++ config.devenv.modules;
      }).type;

      shellPrefix = shellName: if shellName == "default" then "" else "${shellName}-";
    in

    {
      options.devenv.modules = lib.mkOption {
        type = lib.types.listOf lib.types.deferredModule;
        description = ''
          Extra modules to import into every shell.
          Allows flakeModules to add options to devenv for example.
        '';
        default = [
          devenvFlake.flakeModules.readDevenvRoot
        ];
      };
      options.devenv.shells = lib.mkOption {
        type = lib.types.lazyAttrsOf devenvType;
        description = ''
          The [devenv.sh](https://devenv.sh) settings, per shell.

          Each definition `devenv.shells.<name>` results in a value for
          [`devShells.<name>`](flake-parts.html#opt-perSystem.devShells).

          Define `devenv.shells.default` for the default `nix develop`
          invocation - without an argument.
        '';
        example = lib.literalExpression ''
          {
            # create devShells.default
            default = {
              # devenv settings, e.g.
              languages.elm.enable = true;
            };
          }
        '';
        default = { };
      };
      config.devShells = lib.mapAttrs
        (_name: devenv:
          devenv.shell.overrideAttrs (old: {
            nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [
              # Always include full devenv CLI for complete functionality in flake mode
              # Install it as devenv-cli to avoid conflicts with the wrapper
              (pkgs.runCommand "devenv-cli-wrapper" { } ''
                mkdir -p $out/bin
                ln -s ${devenvFlake.packages.${system}.devenv}/bin/devenv $out/bin/devenv-cli
              '')
            ];
            shellHook = (old.shellHook or "") + ''
              # Mark that we're in a flake-based devenv shell with full CLI
              export DEVENV_FLAKE_MODE=1
              export DEVENV_FULL_CLI_AVAILABLE=1
            '';
          })
        )
        config.devenv.shells;

      # Deprecated packages
      # These were used to wire up commands in the devenv shim and are no longer necessary.
      config.packages =
        let
          deprecate = name: value: lib.warn "The package '${name}' is deprecated. Use the corresponding `devenv <cmd>` commands." value;

          # Convert devenv tasks to runnable packages
          mkTaskPackages = shellName: devenv:
            lib.concatMapAttrs
              (taskName: task:
                {
                  "${shellPrefix shellName}task-${taskName}" = pkgs.writeShellScriptBin "devenv-task-${taskName}" ''
                    set -e
                    ${lib.optionalString (task.cwd != null) "cd ${lib.escapeShellArg task.cwd}"}
                    ${lib.optionalString (task.command != null) "exec ${task.command}"}
                  '';
                }
              )
              devenv.tasks;

          # Create a task runner that can execute task graphs
          mkTaskRunner = shellName: devenv:
            {
              "${shellPrefix shellName}tasks-runner" = pkgs.writeShellScriptBin "devenv-tasks-runner" ''
                # Task runner with dependency resolution
                exec ${devenv.task.package}/bin/devenv-tasks "$@"
              '';
            };
        in
        lib.concatMapAttrs
          (shellName: devenv:
            # Existing containers and deprecated packages
            (lib.concatMapAttrs
              (containerName: container:
                { "${shellPrefix shellName}container-${containerName}" = container.derivation; }
              )
              devenv.containers
            ) // lib.mapAttrs deprecate {
              "${shellPrefix shellName}devenv-up" = devenv.procfileScript;
              "${shellPrefix shellName}devenv-test" = devenv.test;
            }
            # New task packages
            // (mkTaskPackages shellName devenv)
            // (mkTaskRunner shellName devenv)
            // {
              # Export task configuration for reuse
              "${shellPrefix shellName}tasks-config" = devenv.task.config;
            }
          )
          config.devenv.shells;
    });

  # the extra parameter before the module make this module behave like an
  # anonymous module, so we need to manually identify the file, for better
  # error messages, docs, and deduplication.
  _file = __curPos.file;
}
