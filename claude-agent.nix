{ config, pkgs, pkgs-unstable, lib, ... }:

let
  hostsLib = import ./hosts.nix { inherit lib; };
  claudeHome = "/var/lib/claude-agent";
  claudeBin = "${pkgs-unstable.claude-code}/bin/claude";
  remoteControlScript = pkgs.writeText "claude-remote-control.exp" ''
    spawn ${claudeBin} remote-control
    expect "y/n"
    send "y\r"
    interact
  '';
in
{
  imports = [ ./common.nix ];

  proxmoxLXC.privileged = lib.mkForce false;

  networking = hostsLib.mkStaticNetwork "claude-agent" // {
    hostName = "claude-agent";
  };

  sops = {
    defaultSopsFile = ./secrets/claude-agent.yaml;
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    secrets.anthropic_api_key = { owner = "claude"; };
    templates."claude-agent.env" = {
      content = "ANTHROPIC_API_KEY=${config.sops.placeholder.anthropic_api_key}";
      owner = "claude";
    };
  };

  users.users.claude = {
    isSystemUser = true;
    group = "claude";
    home = claudeHome;
    createHome = true;
    shell = pkgs.bash;
  };
  users.groups.claude = {};

  environment.systemPackages = with pkgs; [ git openssh jq expect ]
    ++ [ pkgs-unstable.claude-code ];

  systemd.tmpfiles.rules = [
    "d ${claudeHome}         0750 claude claude -"
    "d ${claudeHome}/.claude 0750 claude claude -"
    "d ${claudeHome}/work    0750 claude claude -"
  ];

  systemd.services.claude-agent = {
    description = "Claude Code Remote Agent";
    after = [ "network-online.target" "sops-nix.service" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];

    environment = {
      HOME = claudeHome;
      CLAUDE_CONFIG_DIR = "${claudeHome}/.claude";
    };

    serviceConfig = {
      User = "claude";
      Group = "claude";
      WorkingDirectory = "${claudeHome}/work";
      EnvironmentFile = config.sops.templates."claude-agent.env".path;
      ExecStart = "${pkgs.expect}/bin/expect ${remoteControlScript}";
      Restart = "always";
      RestartSec = "15s";
      NoNewPrivileges = true;
      PrivateTmp = true;
    };
  };
}
