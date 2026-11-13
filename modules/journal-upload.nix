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
    };
  };
}
