{
  description = "Hayabusa";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
  };

  outputs = { self, nixpkgs, ... }:
  let
    systems = [ "x86_64-linux" "aarch64-darwin" ];

    forAllSystems = nixpkgs.lib.genAttrs systems;

    mkPackage = pkgs: pkgs.buildDotnetModule {
      pname = "hayabusa";
      version = "0.0.1";

      src = ./.;
      projectFile = "Hayabusa.csproj";

      dotnet-sdk = pkgs.dotnetCorePackages.sdk_10_0;
      dotnet-runtime = pkgs.dotnetCorePackages.aspnetcore_10_0;

      nugetDeps = ./deps.json;

      executables = [ "Hayabusa" ];

      dotnetFlags = [
        "-c"
        "Release"
        "-p:PublishAot=true"
      ];

      nativeBuildInputs = [
        pkgs.clang
      ];

      buildInputs = [
        pkgs.zlib
      ];
    };
  in
  {
    packages = forAllSystems (system:
      let pkgs = import nixpkgs { inherit system; };
      in {
        default = mkPackage pkgs;
      }
    );

    devShells = forAllSystems (system:
      let
        pkgs = import nixpkgs { inherit system; };
      in {
        default = pkgs.mkShell {
          packages = [
            pkgs.dotnetCorePackages.sdk_10_0
          ];

          DOTNET_ENVIRONMENT = "Development";
          ASPNETCORE_ENVIRONMENT = "Development";
          ASPNETCORE_URLS = "http://localhost:8080";
        };
      }
    );

    apps = forAllSystems (system:
      let
        pkgs = import nixpkgs { inherit system; };
        dotnet = pkgs.dotnetCorePackages.combinePackages [
          pkgs.dotnetCorePackages.sdk_10_0
          pkgs.dotnetCorePackages.aspnetcore_10_0
        ];
      in {
        default = {
          type = "app";
          program = "${pkgs.writeShellScriptBin "hayabusa-dev" ''
            export DOTNET_ROOT="${dotnet}"
            export PATH="${dotnet}/bin:$PATH"

            exec dotnet watch run "$@"
          ''}/bin/hayabusa-dev";
        };
      }
    );

    nixosModules.default = { config, lib, pkgs, ... }:
      let
        cfg = config.services.hayabusa;
        myapp = mkPackage pkgs;
      in {
        options.services.hayabusa = {
          enable = lib.mkEnableOption "Hayabusa";

          port = lib.mkOption {
            type = lib.types.port;
            default = 8080;
            description = "Port on which Hayabusa listens.";
          };

          host = lib.mkOption {
            type = lib.types.str;
            default = "127.0.0.1";
            description = "Address on which Hayabusa listens.";
          };
        };

        config = lib.mkIf cfg.enable {
          users.groups.myapp = {};

          users.users.myapp = {
            isSystemUser = true;
            group = "myapp";
          };

          systemd.services.myapp = {
            description = "Hayabusa";
            wantedBy = [ "multi-user.target" ];
            after = [ "network-online.target" ];
            wants = [ "network-online.target" ];

            serviceConfig = {
              DynamicUser = true;

              ExecStart = "${myapp}/bin/Hayabusa";

              Restart = "on-failure";
              RestartSec = "5s";

              StateDirectory = "hayabusa";
              WorkingDirectory = "/var/lib/hayabusa";

              NoNewPrivileges = true;
              PrivateTmp = true;
              ProtectSystem = "strict";
              ProtectHome = true;
            };

            environment = {
              DOTNET_ENVIRONMENT = "Production";
              ASPNETCORE_ENVIRONMENT = "Production";
              ASPNETCORE_URLS = "http://${cfg.host}:${toString cfg.port}";
            };
          };
        };
      };
  };
}
