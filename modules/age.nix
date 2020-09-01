{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.age;
  users = config.users.users;

  installSecret = secretType: ''
    TMP_DIR=$(mktemp -d)
    TMP_FILE="$TMP_DIR/file"
    (umask 0400; ${pkgs.age}/bin/age --decrypt ${identities} -o "$TMP_FILE" "${secretType.file}")
    install -o '${secretType.owner}' -g '${secretType.group}' -m '${secretType.mode}' "$TMP_FILE" '${secretType.path}'
    rm -rf "$TMP_DIR"
  '';

  installAllSecrets = builtins.concatStringsSep (map installSecret (builtins.attrValues cfg.secrets));

  secretType = types.submodule ({ config, ... }: {
    options = {
      name = mkOption {
        type = types.str;
        default = config._module.args.name;
        description = ''
          Name of the file used in /run/secrets
        '';
      };
      file = mkOption {
        type = types.either types.str types.path;
        description = ''
          Age file the secret is loaded from.
        '';
      };
      path = assert assertMsg (builtins.pathExists config.file) ''
          Cannot find path '${config.file}' set in 'age.secrets."${config._module.args.name}".file'
        '';
        mkOption {
          type = types.str;
          default = "/run/secrets/${config.name}";
          description = ''
            Path where secrets are symlinked to.
            If the default is kept no symlink is created.
          '';
        };
      mode = mkOption {
        type = types.str;
        default = "0400";
        description = ''
          Permissions mode of the in octal.
        '';
      };
      owner = mkOption {
        type = types.str;
        default = "root";
        description = ''
          User of the file.
        '';
      };
      group = mkOption {
        type = types.str;
        default = users.${config.owner}.group;
        description = ''
          Group of the file.
        '';
      };
    };
  });

  identities = builtins.concatStringsSep " " (map (path: "-i ${path}") cfg.sshKeyPaths);

in {
  options.age = {
    secrets = mkOption {
      type = types.attrsOf secretType;
      default = {};
      description = ''
        Attrset of secrets.
      '';
    };
    sshKeyPaths = mkOption {
      type = types.listOf types.path;
      default = if config.services.openssh.enable then
                  map (e: e.path) (lib.filter (e: e.type == "rsa" || e.type == "ed25519") config.services.openssh.hostKeys)
                else [];
      description = ''
        Path to SSH keys to be used as identities in age file decryption.
      '';
    };
  };
  config = mkIf (cfg.secrets != {}) {
    assertions = [{
      assertion = cfg.sshKeyPaths != [];
      message = "Either age.sshKeyPaths must be set.";
    }] ++ map (name: let
      inherit (cfg.secrets.${name}) file;
    in {
      assertion = builtins.isPath file;
      message = "${file} is not in the nix store. Either add it to the nix store.";
    }) (builtins.attrNames cfg.secrets);

    system.activationScripts.setup-secrets = stringAfter [ "users" "groups" ] installAllSecrets;
  };
}
