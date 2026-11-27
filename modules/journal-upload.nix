{ config, pkgs, lib, network, ... }:

# Ship this machine's journal to the prometheus container's
# systemd-journal-remote sink. Imported by both baremetal hosts and every
# container. why: docs/notes.md#prometheus-and-journal-remote
{
  services.journald.upload = {
    enable = true;
    settings.Upload.URL = "http://${network.getIP "prometheus"}:19532";
  };

  # systemd-journal-upload exits on the first DNS/connection failure. Run it
  # in a retry loop so the unit stays `active` for switch-to-configuration
  # (RestartSec=0 still leaves it in activating/auto-restart at check time),
  # and an unresolvable prometheus.internal can never become a tight restart
  # loop that floods the Pi-holes with thousands of queries/s until they
  # rate-limit the UDM (which blackholes LAN DNS). 5s between attempts is
  # plenty for a log shipper.
  systemd.services.systemd-journal-upload = {
    unitConfig.StartLimitIntervalSec = 0;
    serviceConfig = {
      # The empty entry resets the upstream ExecStart list in the drop-in;
      # without it systemd sees two ExecStart= lines and rejects the unit.
      ExecStart = lib.mkForce [
        ""
        (toString (pkgs.writeShellScript "journal-upload-retry" ''
          while true; do
            ${config.systemd.package}/lib/systemd/systemd-journal-upload --save-state || true
            sleep 5
          done
        ''))
      ];
      RestartSec = lib.mkForce "1s";
      # The wrapper shell is now MainPID, so under upstream's NotifyAccess=main
      # the uploader's WATCHDOG=1 pings are dropped and WatchdogSec=3min
      # SIGABRTs the unit every 3 minutes (both processes dump core: ~330
      # coredumps/h on hutch from 9d89a92 until this fix). The loop is the
      # supervisor now. NotifyAccess=all would still fire during an outage,
      # since the uploader exits before it ever pings.
      # why: docs/notes.md#prometheus-and-journal-remote
      WatchdogSec = 0;
    };
  };
}
