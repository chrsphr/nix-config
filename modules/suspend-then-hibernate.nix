{ config, ... }:

# Suspend-then-hibernate (6h delay) on every sleep path. GNOME always calls
# logind's plain Suspend() — idle auto-suspend via gsd-power, menu item via
# gnome-session — and logind never upgrades Suspend() to
# suspend-then-hibernate (only the v256 "sleep" action does that), so
# systemd-suspend.service itself is redirected: GNOME, lid switch, power key
# and `systemctl suspend` all get the 6h hibernate timer through the same
# unit. HibernateOnACPower defaults to true, so the always-on-AC desktop
# hibernates too. Requires boot.resumeDevice + resume_offset (both hosts).
# why: docs/notes.md#suspend-then-hibernate
{
  systemd.sleep.settings.Sleep.HibernateDelaySec = "6h";

  systemd.services.systemd-suspend.serviceConfig.ExecStart = [
    "" # reset the packaged ExecStart before overriding
    "${config.systemd.package}/lib/systemd/systemd-sleep suspend-then-hibernate"
  ];
}
