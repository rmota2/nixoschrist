#flake.nix
{
  description = "NixOS for Raspberry Pi 4 with Pi-hole (Podman) and Mumble (container)";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nixos-generators.url = "github:nix-community/nixos-generators";
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
  };

  outputs = { self, nixpkgs, nixos-generators, nixos-hardware, ... }: let
    system = "aarch64-linux";
    pkgs = nixpkgs.legacyPackages.${system};
  in
  {
    packages.${system} = {
      sdimage = nixos-generators.nixosGenerate {
        system = system;
        format = "sd-aarch64";
        modules = [
          # Raspberry Pi 4 hardware quirks and modules
          nixos-hardware.nixosModules.raspberry-pi-4

          # Primary NixOS configuration
          ({ config, pkgs, lib, ... }: {
            # Use generic extlinux bootloader (PiROM -> bootcode.bin -> U-Boot -> NixOS)
            boot.loader.grub.enable = false;
            boot.loader.generic-extlinux-compatible.enable = true;
            boot.initrd.includeDefaultModules = false;
            # Networking: enable NetworkManager, firewall, and NAT
            networking.networkmanager.enable = true;
            networking.firewall.enable = true;
            networking.nat.enable = true;
            networking.nat.internalInterfaces = [ "ve-+" ];
            networking.nat.externalInterface = "eth0";

            # SSH and console access
            services.openssh.enable = true;
            users.users.nixpi = {
              isNormalUser = true;
              extraGroups = [ "wheel" ];
              password = null;           # no password (use key or autologin)
            };
            services.getty.autologinUser = "nixpi";
            security.sudo.enable = true;  # wheel group gets sudo

            # Podman with Docker compatibility (rootless containers)
            virtualisation.containers.enable = true;
            virtualisation.podman.enable = true;
            virtualisation.podman.dockerCompat = true;

            # Pi-hole in a Podman (OCI) container
            virtualisation.oci-containers.containers.pihole = {
              image = "pihole/pihole:latest";
              autoStart = true;
              ports = [ "0.0.0.0:53:53/udp" "0.0.0.0:80:80" ];
              environment = {
                TZ = "UTC";
                WEBPASSWORD = "yourStrongPassword";
                DNS1 = "8.8.8.8";
                DNS2 = "8.8.4.4";
              };
              volumes = [
                "/var/pihole:/etc/pihole"
                "/var/dnsmasq:/etc/dnsmasq.d"
              ];
            };

            # Mumble (Murmur) in a NixOS container
            containers.murmur = {
              autoStart = true;
              privateNetwork = true;
              hostAddress = "192.168.100.2";
              localAddress = "192.168.100.3";
              config = { config, pkgs, lib, ... }: {
                system.stateVersion = "24.05";
                services.murmur.enable = true;
                networking.firewall.enable = true;
                networking.useHostResolvConf = lib.mkForce false;
              };
            };

            # System state version
            system.stateVersion = "24.05";
          })
        ];
      };
    };
  };
}
