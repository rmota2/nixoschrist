{
  description = "NixOS Pi SD Image";
  
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
  };
  
  outputs = { self, nixpkgs, ... }:
    let
      system = "aarch64-linux";
    in {
      nixosConfigurations.installer = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          "${nixpkgs}/nixos/modules/installer/sd-card/sd-image-aarch64.nix"
          ({ config, pkgs, lib, ... }: {
            # Avoid the modules-shrunk issue
            system.build.initialRamdisk = lib.mkForce (
              pkgs.makeInitrdNG {
                inherit (config.boot.initrd) compressor compressorArgs prepend;
                contents = config.boot.initrd.contents;
              }
            );
            
            # Minimal boot configuration
            boot.initrd.includeDefaultModules = false;
            boot.initrd.availableKernelModules = lib.mkForce [
              "mmc_block"
              "usbhid"
              "hid_generic"
              "hid"
            ];
            
            # SD card configuration
            sdImage.firmwareSize = 512;
            sdImage.compressImage = false;  # Compress later in CI
            
            # System configuration
            system.stateVersion = "25.05";
            networking.hostName = "nixos";
            
            # Enable SSH
            services.openssh = {
              enable = true;
              settings.PermitRootLogin = "yes";
            };
            
            # Create user
            users.users.nixpi = {
              isNormalUser = true;
              extraGroups = [ "wheel" "networkmanager" ];
              initialPassword = "changeme";
              openssh.authorizedKeys.keys = [
                # Add your SSH key here
              ];
            };
            
            users.users.root.initialPassword = "changeme";
            
            # Networking
            networking.networkmanager.enable = true;
            networking.firewall.enable = true;
            
            # Enable flakes
            nix.settings.experimental-features = [ "nix-command" "flakes" ];
            
            # Include your main config in the image
            environment.etc."nixos/configuration.nix".text = ''
              { config, pkgs, lib, ... }:
              {
                imports = [ ./hardware-configuration.nix ];
                
                system.stateVersion = "25.05";
                nix.settings.experimental-features = [ "nix-command" "flakes" ];
                
                networking.hostName = "nixos";
                networking.networkmanager.enable = true;
                
                services.openssh.enable = true;
                
                # Enable Podman
                virtualisation.podman = {
                  enable = true;
                  dockerCompat = true;
                };
                
                # Firewall
                networking.firewall = {
                  enable = true;
                  allowedTCPPorts = [ 22 80 64738 ];
                  allowedUDPPorts = [ 53 64738 ];
                };
                
                # Your user
                users.users.nixpi = {
                  isNormalUser = true;
                  extraGroups = [ "wheel" "podman" "networkmanager" ];
                };
                
                # Pi-hole service
                systemd.services.pihole = {
                  description = "Pi-hole DNS Server";
                  after = [ "network.target" ];
                  wantedBy = [ "multi-user.target" ];
                  
                  serviceConfig = {
                    Type = "simple";
                    Restart = "always";
                    RestartSec = "5s";
                    ExecStartPre = "''${pkgs.podman}/bin/podman pull pihole/pihole:latest";
                    ExecStart = '''
                      ''${pkgs.podman}/bin/podman run \
                        --rm \
                        --name pihole \
                        -e TZ=UTC \
                        -e WEBPASSWORD=changeme \
                        -e SERVERIP=192.168.1.208 \
                        -v pihole-data:/etc/pihole \
                        -v pihole-dnsmasq:/etc/dnsmasq.d \
                        -p 53:53/tcp -p 53:53/udp -p 80:80/tcp \
                        pihole/pihole:latest
                    ''';
                    ExecStop = "''${pkgs.podman}/bin/podman stop pihole";
                  };
                };
                
                # Mumble
                containers.mumble = {
                  autoStart = true;
                  privateNetwork = true;
                  hostAddress = "10.0.3.1";
                  localAddress = "10.0.3.2";
                  
                  config = { config, pkgs, ... }: {
                    system.stateVersion = "25.05";
                    services.murmur = {
                      enable = true;
                      welcometext = "Welcome to Mumble!";
                      password = "changeme";
                      port = 64738;
                    };
                    networking.firewall = {
                      enable = true;
                      allowedTCPPorts = [ 64738 ];
                      allowedUDPPorts = [ 64738 ];
                    };
                  };
                };
              }
            '';
          })
        ];
      };
    };
}