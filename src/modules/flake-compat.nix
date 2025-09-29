{ config
, pkgs
, lib
, ...
}:

let
  version = lib.fileContents ./latest-version;
  shellName = config._module.args.name or "default";

  nixFlags = "--show-trace --extra-experimental-features nix-command --extra-experimental-features flakes";

  # Helper function to wrap commands with nix develop
  #
  # This is skipped if the user is already in a shell launched by direnv.
  # We trust that direnv will handle reloads.
  wrapWithNixDevelop = command: args: ''
    if [[ -n "$IN_NIX_SHELL" && "$DEVENV_IN_DIRENV_SHELL" == "true" ]]; then
      exec ${command} ${args}
    else
      exec nix develop .#${shellName} --impure ${nixFlags} -c ${command} ${args}
    fi
  '';

  # Flake integration wrapper for devenv CLI
  devenv-flake-wrapper = pkgs.writeScriptBin "devenv" ''
    #!/usr/bin/env bash

    # we want subshells to fail the program
    set -e

    command=$1
    if [[ ! -z $command ]]; then
      shift
    fi

    # Check if full CLI is available and should be used
    use_full_cli() {
      # Only use full CLI if we're in a shell that has it available
      # The full CLI is installed as 'devenv' but we need to distinguish it from this wrapper
      [[ "$DEVENV_FULL_CLI_AVAILABLE" == "1" ]] && command -v devenv-cli >/dev/null 2>&1
    }

    case $command in
      up)
        # Re-enter the shell to ensure we use the latest configuration
        ${wrapWithNixDevelop "devenv-flake-up" "\"$@\""}
        ;;

      test)
        # Re-enter the shell to ensure we use the latest configuration
        ${wrapWithNixDevelop "devenv-flake-test" "\"$@\""}
        ;;

      version)
        echo "devenv: ${version}"
        ;;

      tasks)
        if use_full_cli; then
          # Pass through to full CLI with flake-aware mode
          exec devenv-cli --flake-mode tasks "$@"
        else
          echo "Tasks functionality requires the full devenv CLI."
          echo "This should be automatically available in flake-parts environments."
          echo "Available tasks commands would be: run, list"
          exit 1
        fi
        ;;

      shell|info|update|search|inputs|build|gc|repl|container|generate|init|direnvrc)
        if use_full_cli; then
          # Pass through to full CLI with flake-aware mode
          exec devenv-cli --flake-mode "$command" "$@"
        else
          echo "Command '$command' requires the full devenv CLI."
          echo "This should be automatically available in flake-parts environments."
          echo ""
          echo "Available commands in basic flake mode:"
          echo "  up       - Start processes"
          echo "  test     - Run tests"
          echo "  version  - Show version"
          exit 1
        fi
        ;;

      *)
        echo "https://devenv.sh (version ${version}): Fast, Declarative, Reproducible, and Composable Developer Environments"
        echo
        if use_full_cli; then
          echo "Full devenv CLI functionality is available in this flake environment."
          echo
          echo "Usage: devenv <command> [args...]"
          echo
          echo "Common commands:"
          echo "  up              Start processes in foreground"
          echo "  test            Run tests"
          echo "  tasks           Manage and run tasks"
          echo "  shell           Enter development shell"
          echo "  info            Show environment information"
          echo "  version         Display devenv version"
          echo
          echo "For complete command list, run: devenv --help"
        else
          echo "This is a flake integration wrapper with basic functionality."
          echo "Full CLI should be automatically available in flake-parts environments."
          echo
          echo "Usage: devenv command"
          echo
          echo "Available commands:"
          echo "  test            Run tests"
          echo "  up              Start processes in foreground"
          echo "  version         Display devenv version"
        fi
        echo
        exit 1
    esac
  '';

  # `devenv up` helper command
  devenv-flake-up =
    pkgs.writeShellScriptBin "devenv-flake-up" ''
      ${lib.optionalString (config.processes == { }) ''
        echo "No 'processes' option defined: https://devenv.sh/processes/" >&2
        exit 1
      ''}
      exec ${config.procfileScript} "$@"
    '';

  # `devenv test` helper command
  devenv-flake-test =
    pkgs.writeShellScriptBin "devenv-flake-test" ''
      exec ${config.test} "$@"
    '';

  devenvFlakeCompat = pkgs.symlinkJoin {
    name = "devenv-flake-compat";
    paths = [
      devenv-flake-wrapper
      devenv-flake-up
      devenv-flake-test
    ];
  };
in
{
  config = lib.mkIf config.devenv.flakesIntegration {
    env.DEVENV_FLAKE_SHELL = shellName;

    # Add the flake command helpers directly to the path.
    # This is to avoid accidentally adding their paths to env vars, like DEVENV_PROFILE.
    # If that happens and a profile command is provided the full env, we will create a recursive dependency between the env and the procfile command.
    enterShell = ''
      export PATH=${devenvFlakeCompat}/bin:$PATH
    '';
  };
}
