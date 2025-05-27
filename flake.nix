{
  description = "NixOS Pi – Pi-hole & Mumble (aarch64)";
  
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
  };
  
  outputs = { self, nixpkgs, ... }:
    let
      system = "aarch64-linux";
      
      # Shared configuration module
      commonConfig = { config, pkgs, lib, ... }: {
        # System basics
        system.stateVersion = "25.05";
        
        # Enable flakes
        nix.settings.experimental-features = [ "nix-command" "flakes" ];
        
        # Hostname
        networking.hostName = "nixos";
        
        # Boot loader for Raspberry Pi
        boot.loader.grub.enable = false;
        boot.loader.generic-extlinux-compatible.enable = true;
        boot.loader.generic-extlinux-compatible.configurationLimit = 1;
        
        # File systems
        fileSystems."/" = {
          device = "/dev/disk/by-label/NIXOS_SD";
          fsType = "ext4";
        };
        
        fileSystems."/boot" = {
          device = "/dev/disk/by-label/FIRMWARE";
          fsType = "vfat";
        };
        
        # Enable Podman for containers
        virtualisation.podman = {
          enable = true;
          dockerCompat = true;
        };
        
        # Networking
        networking.networkmanager.enable = true;
        networking.firewall = {
          enable = true;
          allowedTCPPorts = [ 22 80 64738 ];  # SSH, Pi-hole web, Mumble
          allowedUDPPorts = [ 53 64738 ];     # DNS, Mumble
        };
        
        # NAT for containers
        networking.nat = {
          enable = true;
          internalInterfaces = [ "ve-+" "podman0" ];
          externalInterface = "end0";
        };
        
        # Enable SSH
        services.openssh.enable = true;
        
        # Security
        security.sudo.enable = true;
        security.sudo.wheelNeedsPassword = true;
        
        # Getty service (no autologin for security)
        services.getty = {
          autologinOnce = false;
          # Remove autologinUser for headless setup
        };
        
        # Users
        users.users.nixpi = {
          isNormalUser = true;
          extraGroups = [ "wheel" "podman" "networkmanager" ];
          initialPassword = "admin";  # CHANGE THIS!
          openssh.authorizedKeys.keys = [
            # Add your SSH public key here for passwordless access
            # "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQ... your-key@machine"
          ];
        };
        
        # Systemd service for Pi-hole container
        systemd.services.pihole = {
          description = "Pi-hole DNS Server";
          after = [ "network.target" ];
          wantedBy = [ "multi-user.target" ];
          
          serviceConfig = {
            Type = "simple";
            Restart = "always";
            RestartSec = "5s";
            ExecStartPre = "${pkgs.podman}/bin/podman pull pihole/pihole:latest";
            ExecStart = ''
              ${pkgs.podman}/bin/podman run \
                --rm \
                --name pihole \
                --hostname pihole \
                -e TZ=UTC \
                -e WEBPASSWORD=changeme \
                -e SERVERIP=192.168.1.208 \
                -v pihole-data:/etc/pihole \
                -v pihole-dnsmasq:/etc/dnsmasq.d \
                -p 53:53/tcp \
                -p 53:53/udp \
                -p 80:80/tcp \
                pihole/pihole:latest
            '';
            ExecStop = "${pkgs.podman}/bin/podman stop pihole";
          };
        };
        
        # Mumble container
        containers.mumble = {
          autoStart = true;
          privateNetwork = true;
          hostAddress = "10.0.3.1";
          localAddress = "10.0.3.2";
          
          config = { config, pkgs, ... }: {
            system.stateVersion = "25.05";
            
            # Mumble server service
            services.murmur = {
              enable = true;
              welcometext = "Welcome to Mumble on NixOS!";
              bandwidth = 72000;
              users = 100;
              password = "changeme";  # CHANGE THIS!
              port = 64738;
            };
            
            # Container firewall
            networking.firewall = {
              enable = true;
              allowedTCPPorts = [ 64738 ];
              allowedUDPPorts = [ 64738 ];
            };
          };
        };
      };
      
    in {
      # Regular system configuration
      nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [ commonConfig ];
      };
      
      # SD card image builder configuration
      nixosConfigurations.installer = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          # Base Raspberry Pi SD image
          "${nixpkgs}/nixos/modules/installer/sd-card/sd-image-aarch64.nix"
          
          # Include common configuration
          commonConfig
          
          # SD image specific settings
          ({ config, pkgs, lib, ... }: {
            # Increase boot partition size
            sdImage.firmwarePartitionOffset = 32;
            sdImage.firmwareSize = 256;  # 256MB boot partition
            
            # Ensure SSH starts on first boot
            systemd.services.sshd.wantedBy = lib.mkForce [ "multi-user.target" ];
            
            # Compress the image
            sdImage.compressImage = true;
          })
        ];
      };
      
      # Build target for GitHub Actions
      packages.${system} = {
        sdImage = self.nixosConfigurations.installer.config.system.build.sdImage;
      };
    };
}