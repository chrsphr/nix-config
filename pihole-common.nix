{ config, pkgs, lib, ... }:

{
  ### Networking (adjust IP as needed)
  networking = {
    useDHCP = false;
    interfaces.eth0.ipv4.addresses = [{
      address = "192.168.1.9";
      prefixLength = 24;
    }];
    defaultGateway = {
    address = "192.168.1.1";
    interface = "eth0";
    };
    nameservers = [ "1.1.1.1" ];
  };

  services.pihole-ftl = {
    enable = true;
    openFirewallDHCP = true;
    queryLogDeleter.enable = true;
    lists = [
      {
        url = "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts";
        # Alternatively, use the file from nixpkgs. Note its contents won't be
        # automatically updated by Pi-hole, as it would with an online URL.
        # url = "file://${pkgs.stevenblack-blocklist}/hosts";
        description = "Steven Black's unified adlist";
      }
    ];
    settings = {
      dns = {
        domainNeeded = true;
        expandHosts = true;
        interface = "eth0";
        listeningMode = "BIND";
        upstreams = [ "1.1.1.1" ];
      };
      dhcp = {
        active = false;

      };

    };
  };

    {
    services.pihole-web = {
        enable = true;
        ports = [ 80 ];
    };
    }



  ### Packages
  environment.systemPackages = with pkgs; [
    dig
  ];




}
