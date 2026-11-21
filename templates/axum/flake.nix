{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
    rust-toolchains = {
      url = "github:giodamelio/rust-toolchains";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs @ {
    self,
    flake-parts,
    rust-toolchains,
    ...
  }: let
    # Renaming the crate in Cargo.toml renames the package, the NixOS options
    # and the systemd units with it.
    inherit ((builtins.fromTOML (builtins.readFile ./Cargo.toml)).package) name version;
  in
    flake-parts.lib.mkFlake {inherit inputs;} {
      imports = [rust-toolchains.flakeModules.default];

      systems = ["x86_64-linux" "aarch64-linux" "aarch64-darwin"];

      perSystem = {
        config,
        lib,
        pkgs,
        system,
        ...
      }: {
        rust-toolchains.channel = "stable";

        packages.default = config.rust-toolchains.rustPlatform.buildRustPackage {
          pname = name;
          inherit version;
          src = ./.;
          cargoLock.lockFile = ./Cargo.lock;
          meta.mainProgram = name;
        };

        # NixOS VM tests need a Linux builder with KVM, and only x86_64-linux
        # is assumed to have one.
        checks = lib.optionalAttrs (system == "x86_64-linux") {
          nixos-vm = pkgs.testers.runNixOSTest {
            name = "${name}-socket-activation";
            nodes.machine = {pkgs, ...}: {
              imports = [self.nixosModules.default];
              services.${name}.enable = true;
              environment.systemPackages = [pkgs.curl];
            };
            # With Type=notify the service only becomes active once it has
            # sent READY=1, so reaching active state proves the notification.
            testScript = ''
              machine.wait_for_unit("${name}.socket")
              machine.require_unit_state("${name}.service", "inactive")

              machine.succeed('test "$(curl --fail --silent http://127.0.0.1:8000/health)" = ok')
              machine.wait_for_unit("${name}.service")
              machine.succeed('test "$(systemctl show --property=Type --value ${name}.service)" = notify')

              machine.systemctl("stop ${name}.service")
              machine.wait_until_succeeds("journalctl --unit=${name}.service --grep='shutting down'")
              machine.succeed('test "$(curl --fail --silent http://127.0.0.1:8000/health)" = ok')
            '';
          };
        };
      };

      flake.nixosModules.default = {
        config,
        lib,
        pkgs,
        ...
      }: let
        cfg = config.services.${name};
      in {
        options.services.${name} = {
          enable = lib.mkEnableOption "the ${name} HTTP server";
          package = lib.mkOption {
            type = lib.types.package;
            default = self.packages.${pkgs.stdenv.hostPlatform.system}.default;
            defaultText = lib.literalExpression "self.packages.\${pkgs.stdenv.hostPlatform.system}.default";
            description = "The ${name} package to run.";
          };
          listenStream = lib.mkOption {
            type = lib.types.str;
            default = "127.0.0.1:8000";
            example = "[::]:8080";
            description = "TCP address the socket unit listens on, in the form systemd's `ListenStream=` takes. A bare port listens on every address.";
          };
        };

        config = lib.mkIf cfg.enable {
          systemd.sockets.${name} = {
            description = "${name} HTTP socket";
            wantedBy = ["sockets.target"];
            listenStreams = [cfg.listenStream];
          };

          systemd.services.${name} = {
            description = "${name} HTTP server";
            requires = ["${name}.socket"];
            after = ["${name}.socket"];
            serviceConfig = {
              Type = "notify";
              ExecStart = lib.getExe cfg.package;
              Restart = "on-failure";

              DynamicUser = true;
              CapabilityBoundingSet = "";
              LockPersonality = true;
              MemoryDenyWriteExecute = true;
              NoNewPrivileges = true;
              PrivateDevices = true;
              PrivateTmp = true;
              PrivateUsers = true;
              ProcSubset = "pid";
              ProtectClock = true;
              ProtectControlGroups = true;
              ProtectHome = true;
              ProtectHostname = true;
              ProtectKernelLogs = true;
              ProtectKernelModules = true;
              ProtectKernelTunables = true;
              ProtectProc = "invisible";
              ProtectSystem = "strict";
              # AF_UNIX is for the sd_notify socket.
              RestrictAddressFamilies = ["AF_UNIX" "AF_INET" "AF_INET6"];
              RestrictNamespaces = true;
              RestrictRealtime = true;
              RestrictSUIDSGID = true;
              # The socket unit owns the listening socket, so a bind here means
              # the service missed LISTEN_FDS and fell back to its own address.
              SocketBindDeny = "any";
              SystemCallArchitectures = "native";
              SystemCallFilter = ["@system-service" "~@privileged" "~@resources"];
              UMask = "0077";
            };
          };
        };
      };
    };
}
