{ config, pkgs, lib, ... }:

# USB/IP: project a USB device (the DVB tuner on minihutch) onto another host
# (hutch, where Plex runs) over the LAN. Server and client MUST run the same
# kernel version — the usbip userspace is kernel-matched.
# why: docs/notes.md#usbip-tuner-design, #kernel-pin

let
  cfg = config.usbipTuner;
  usbip = "${config.boot.kernelPackages.usbip}/bin/usbip";
  usbipd = "${config.boot.kernelPackages.usbip}/bin/usbipd";
in
{
  options.usbipTuner = {
    export = {
      enable = lib.mkEnableOption "exporting a local USB device over USB/IP";

      busid = lib.mkOption {
        type = lib.types.str;
        example = "3-1";
        description = ''
          Kernel bus id of the device to export, as shown by `usbip list -l`
          or the directory name under /sys/bus/usb/devices/. NOT stable across
          port changes — move the dongle to a different socket and this
          changes. The udev rule below re-binds on replug by vendor/product,
          so a moved dongle recovers on its own; this value only seeds the
          boot-time bind.
        '';
      };

      idVendor = lib.mkOption {
        type = lib.types.str;
        example = "045e";
        description = "USB idVendor, used by the replug udev rule.";
      };

      idProduct = lib.mkOption {
        type = lib.types.str;
        example = "02d5";
        description = "USB idProduct, used by the replug udev rule.";
      };

      allowFrom = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "192.168.1.2";
        description = ''
          Source IP allowed to reach usbipd on tcp/3240. null opens the port
          to the whole LAN. usbipd has no authentication whatsoever — anyone
          who can reach the port can claim the device — so pin this.
        '';
      };
    };

    attach = {
      enable = lib.mkEnableOption "attaching a remote USB device over USB/IP";

      server = lib.mkOption {
        type = lib.types.str;
        example = "192.168.1.3";
        description = "IP of the host running usbipd with the device bound.";
      };

      busid = lib.mkOption {
        type = lib.types.str;
        example = "3-1";
        description = "Bus id of the device ON THE SERVER (not local).";
      };

      preCreate = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        example = [ "/dev/dvb" ];
        description = ''
          Directories to create on devtmpfs so they exist even when the remote
          device is absent. Without this, anything bind-mounting the device
          path (e.g. a container) fails to start whenever the tuner or its
          host is unreachable — coupling unrelated services to the tuner's
          availability. The kernel populates the directory when the device
          attaches, and entries appear through existing bind mounts.
        '';
      };
    };
  };

  config = lib.mkMerge [

    # ── Server: the host the device is physically plugged into ──────────────
    (lib.mkIf cfg.export.enable {
      boot.kernelModules = [ "usbip_host" ];
      environment.systemPackages = [ config.boot.kernelPackages.usbip ];

      systemd.services.usbipd = {
        description = "USB/IP device server";
        wantedBy = [ "multi-user.target" ];
        after = [ "network.target" ];
        serviceConfig = {
          ExecStart = usbipd;
          Restart = "always";
          RestartSec = "5s";
        };
      };

      # Boot-time bind. `usbip bind` exits non-zero when the device is already
      # bound, which is a no-op, not a failure — hence the `|| true`.
      systemd.services.usbip-bind = {
        description = "Bind ${cfg.export.busid} to the usbip-host driver";
        wantedBy = [ "multi-user.target" ];
        after = [ "usbipd.service" ];
        requires = [ "usbipd.service" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = "${usbip} bind -b ${cfg.export.busid} || true";
        preStop = "${usbip} unbind -b ${cfg.export.busid} || true";
      };

      # Re-bind on replug (and on a move to a different port, where the busid
      # changes and the static bind above would be pointing at nothing).
      services.udev.extraRules = ''
        ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="${cfg.export.idVendor}", ATTR{idProduct}=="${cfg.export.idProduct}", RUN+="${usbip} bind -b $kernel"
      '';

      networking.firewall = lib.mkMerge [
        (lib.mkIf (cfg.export.allowFrom == null) {
          allowedTCPPorts = [ 3240 ];
        })
        (lib.mkIf (cfg.export.allowFrom != null) {
          extraCommands = ''
            iptables -A nixos-fw -p tcp --dport 3240 -s ${cfg.export.allowFrom} -j nixos-fw-accept
          '';
        })
      ];
    })

    # ── Client: the host that wants the device ──────────────────────────────
    (lib.mkIf cfg.attach.enable {
      boot.kernelModules = [ "vhci_hcd" ];
      environment.systemPackages = [ config.boot.kernelPackages.usbip ];

      systemd.tmpfiles.rules =
        map (d: "d ${d} 0755 root root -") cfg.attach.preCreate;

      # Supervisor loop, not a oneshot: re-attaches automatically after server
      # reboots, replugs and LAN blips. why: docs/notes.md#usbip-tuner-design
      systemd.services.usbip-attach = {
        description = "Attach USB/IP device ${cfg.attach.busid} from ${cfg.attach.server}";
        wantedBy = [ "multi-user.target" ];
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        serviceConfig = {
          Restart = "always";
          RestartSec = "30s";
        };
        script = ''
          while true; do
            if ! ${usbip} port 2>/dev/null | grep -q "${cfg.attach.server}"; then
              ${usbip} attach -r ${cfg.attach.server} -b ${cfg.attach.busid} \
                && echo "attached ${cfg.attach.busid} from ${cfg.attach.server}" \
                || echo "attach failed; retrying in 30s"
            fi
            sleep 30
          done
        '';
      };
    })
  ];
}
