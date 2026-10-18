{ config, lib, pkgs, utils, ... }:

# Forwards plain-text log files into the journal so they reach fleet-logs.
# journal-upload only ships the journal, so an app that writes its own log file
# is invisible without this. Each entry runs a unit that tails one file and tags
# its lines with SYSLOG_IDENTIFIER=<name>: `fleet-logs -t <name>`.

let
  cfg = config.services.fileLogs;
in
{
  options.services.fileLogs = lib.mkOption {
    type = lib.types.attrsOf lib.types.str;
    default = { };
    example = {
      plex = "/var/lib/plex/Plex Media Server/Logs/Plex Media Server.log";
    };
    description = "Log files to tail into the journal, keyed by syslog identifier.";
  };

  config.systemd.services = lib.mapAttrs' (name: path:
    lib.nameValuePair "file-log-${name}" {
      description = "Forward ${path} to the journal";
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        ExecStart = utils.escapeSystemdExecArgs [
          "${pkgs.coreutils}/bin/tail"
          "--lines=0"
          "--follow=name"
          "--retry"
          path
        ];
        SyslogIdentifier = name;
        Restart = "always";
        RestartSec = "10s";
      };
    }
  ) cfg;
}
