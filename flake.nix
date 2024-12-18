{
  description = "Aeon development environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    pyproject-build-systems.url = "github:pyproject-nix/build-system-pkgs";
    pyproject-build-systems.inputs.pyproject-nix.follows = "pyproject-nix";
    pyproject-build-systems.inputs.uv2nix.follows = "uv2nix";
    pyproject-build-systems.inputs.nixpkgs.follows = "nixpkgs";

    pyproject-nix.url = "github:pyproject-nix/pyproject.nix";
    pyproject-nix.inputs.nixpkgs.follows = "nixpkgs";

    uv2nix.url = "github:pyproject-nix/uv2nix";
    uv2nix.inputs.pyproject-nix.follows = "pyproject-nix";
    uv2nix.inputs.nixpkgs.follows = "nixpkgs";

    uv2nix_hammer_overrides.url = "github:TyberiusPrime/uv2nix_hammer_overrides";
    uv2nix_hammer_overrides.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    {
      nixpkgs,
      pyproject-build-systems,
      pyproject-nix,
      uv2nix,
      uv2nix_hammer_overrides,
      ...
    }:
    let
      inherit (nixpkgs) lib;
      system = "x86_64-linux";
      workspace = uv2nix.lib.workspace.loadWorkspace { workspaceRoot = ./.; };
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
      python = pkgs.python3;
      pyprojectOverrides = uv2nix_hammer_overrides.overrides pkgs;
      overlay = lib.composeManyExtensions [
        pyproject-build-systems.overlays.default
        (workspace.mkPyprojectOverlay { sourcePreference = "wheel"; })
        (workspace.mkEditablePyprojectOverlay { root = "$PROJ_ROOT"; })
      ];
      baseSet =
        (pkgs.callPackage pyproject-nix.build.packages {
          inherit python;
        }).overrideScope
          overlay;
      pythonSet = baseSet.pythonPkgsHostHost.overrideScope pyprojectOverrides;
      pythonEnv = pythonSet.mkVirtualEnv "aeon-env" workspace.deps.all;
    in
    {
      packages.${system}.default = pythonEnv;
      devShells.${system} = {
        impure = pkgs.mkShell {
          packages = [
            python
            pkgs.uv
          ];
          shellHook = ''
            # Undo dependency propagation by Nixpkgs.
            unset PYTHONPATH
            export PROJ_ROOT="$(git rev-parse --show-toplevel)"
            export PATH="$PROJ_ROOT/scripts:$PATH"
          '';
        };
        default = pkgs.mkShell {
          packages = [
            # Python environment.
            pythonEnv
            python

            # Binaries.
            pkgs.pyright
            pkgs.ruff
            pkgs.uv
          ];
          shellHook = ''
            # Undo dependency propagation by Nixpkgs.
            unset PYTHONPATH

            # Project.
            export PROJ_ROOT="$(git rev-parse --show-toplevel)"

            # Uv.
            #
            # Use Nix as much as possible, but there are minor problems. For
            # example, the `tests` directories are not distributed and should
            # therefore not be accessible from non-test code. However, `pyright`
            # does detect non-distributed files and does not point out import
            # errors.
            export UV_NO_CACHE=1
            export UV_NO_CONFIG=1
            export UV_NO_ENV_FILE=1
            export UV_NO_SYNC=1
            export UV_PROJECT_ENVIRONMENT=${pythonEnv}
            export UV_PYTHON_DOWNLOADS=never
            export UV_PYTHON_PREFERENCE=only-system
          '';
        };
      };
    };
}
