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


  # Open firewall ports
  networking.firewall = {
    allowedTCPPorts = [ 22 53 80 ];
    allowedUDPPorts = [ 53 ];
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
        upstreams = [
            "208.67.222.222"
            "208.67.220.220"
            "2620:119:35::35"
            "2620:119:53::53"
        ];
      };
      dhcp = {
        active = false;

      };
      webserver.api = {
        pwhash = "$BALLOON-SHA256$v=1$s=1024,t=32$0ryHODlDWJn1L0uBamA2Zg==$zq/YS/1/qOqhbXbcoKGf7hdWWVv3Tqd0Dn7iVwYKAf4=";
      };
    };
  };


    services.pihole-web = {
        enable = true;
        ports = [ 80 ];
    };




  ### Packages
  environment.systemPackages = with pkgs; [
    dig
  ];




}
