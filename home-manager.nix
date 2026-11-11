{ self }:
{
  config,
  lib,
  pkgs,
  options,
  ...
}:
let
  cfg = config.programs.copai-shell;
  inherit (lib) mkOption mkEnableOption types;
  fraction = types.addCheck types.number (n: n >= 0 && n <= 1);
  hasNiri = options ? programs.niri.settings;
  launcher = pkgs.writeShellScriptBin "copai-shell" ''
    export COPAI_ENV_FILE=${lib.escapeShellArg cfg.environmentFile}
    export COPAI_OVERLAY_SETTINGS=${lib.escapeShellArg (builtins.toJSON (cfg.appearance // cfg.timing))}
    ${lib.optionalString (cfg.model != null) "export COPAI_MODEL=${lib.escapeShellArg cfg.model}"}
    exec ${lib.getExe cfg.package} "$@"
  '';
in
{
  options.programs.copai-shell = {
    enable = mkEnableOption "the Copai Wayland overlay";
    package = mkOption {
      type = types.package;
      default = self.packages.${pkgs.stdenv.hostPlatform.system}.default;
      description = "Copai shell package to run.";
    };
    environmentFile = mkOption {
      type = types.str;
      default = "${config.home.homeDirectory}/documents/licenses/copai.env";
      description = "Absolute runtime path to the API-key file. Use a string, not a Nix path literal; the contents are never read by Nix.";
    };
    model = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Model override. Null uses COPAI_MODEL in the key file, or gpt-5-nano.";
    };
    autostart = mkOption {
      type = types.bool;
      default = true;
      description = "Start with Niri when integration is enabled, otherwise via a graphical-session user service.";
    };
    niri = {
      enable = mkEnableOption "Niri shortcut integration (requires the Niri Home Manager module)";
      askKey = mkOption {
        type = types.str;
        default = "Mod+K";
        description = "Shortcut to submit the clipboard.";
      };
      revealKey = mkOption {
        type = types.str;
        default = "Mod+I";
        description = "Hold this shortcut to reveal the answer.";
      };
    };
    appearance = {
      opacity = mkOption {
        type = fraction;
        default = 0.18;
        description = "Text opacity from 0 to 1.";
      };
      color = mkOption {
        type = types.str;
        default = "#ffffff";
        description = "QML text color.";
      };
      fontSize = mkOption {
        type = types.ints.positive;
        default = 14;
        description = "Font size in logical pixels.";
      };
      xFraction = mkOption {
        type = fraction;
        default = 0.25;
        description = "Horizontal offset as a fraction of screen width.";
      };
      widthFraction = mkOption {
        type = fraction;
        default = 0.22;
        description = "Text width as a fraction of screen width.";
      };
      y = mkOption {
        type = types.ints.unsigned;
        default = 2;
        description = "Vertical offset in logical pixels.";
      };
      height = mkOption {
        type = types.ints.positive;
        default = 32;
        description = "Text area height in logical pixels.";
      };
      maxLines = mkOption {
        type = types.ints.positive;
        default = 2;
        description = "Maximum number of visible lines.";
      };
    };
    timing = {
      hideDelay = mkOption {
        type = types.ints.positive;
        default = 60;
        description = "Hide timeout in milliseconds; must exceed the keyboard repeat interval.";
      };
      initialDelay = mkOption {
        type = types.ints.positive;
        default = 550;
        description = "Initial timeout in milliseconds; must exceed the keyboard repeat delay.";
      };
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        assertions = [
          {
            assertion = lib.hasPrefix "/" cfg.environmentFile;
            message = "programs.copai-shell.environmentFile must be an absolute runtime path.";
          }
          {
            assertion = !cfg.niri.enable || hasNiri;
            message = "Copai Niri integration requires the Niri Home Manager module.";
          }
          {
            assertion = cfg.niri.askKey != cfg.niri.revealKey;
            message = "Copai ask and reveal shortcuts must be different.";
          }
        ];
        home.packages = [ launcher ];
        systemd.user.services.copai-shell = lib.mkIf (cfg.autostart && !cfg.niri.enable) {
          Unit = {
            Description = "Copai Wayland overlay";
            After = [ "graphical-session-pre.target" ];
            PartOf = [ "graphical-session.target" ];
          };
          Service = {
            ExecStart = "${lib.getExe launcher} --no-duplicate";
            Restart = "on-failure";
          };
          Install.WantedBy = [ "graphical-session.target" ];
        };
      }
      (lib.optionalAttrs hasNiri {
        programs.niri.settings = lib.mkIf cfg.niri.enable {
          spawn-at-startup = lib.mkIf cfg.autostart [
            {
              argv = [
                (lib.getExe launcher)
                "--no-duplicate"
              ];
            }
          ];
          binds = {
            ${cfg.niri.askKey} = {
              repeat = false;
              action.spawn = [
                (lib.getExe launcher)
                "ipc"
                "call"
                "copai"
                "ask"
              ];
            };
            ${cfg.niri.revealKey} = {
              repeat = true;
              action.spawn = [
                (lib.getExe launcher)
                "ipc"
                "call"
                "copai"
                "reveal"
              ];
            };
          };
        };
      })
    ]
  );
}
