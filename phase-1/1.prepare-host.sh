# Update system and install essential tools
sudo apt update && sudo apt upgrade -y
sudo apt install -y curl git wget unzip build-essential cpu-checker

# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER

# Install Docker Compose v2
# if you installed docker from docker official site, just run 'sudo apt install -y docker-compose-plugin docker-buildx-plugin'
# else you still want to use docker from debian release, manually install docker compose v2 and docker buildx plugins following the instructions at https://github.com/docker/{compose, buildx} 

# Verify and enable KVM for Android emulation
sudo apt install -y qemu-kvm libvirt-daemon-system libvirt-clients bridge-utils
sudo adduser $USER kvm
sudo adduser $USER libvirt
sudo kvm-ok  # Should return "KVM acceleration can be used"

# Install Android emulator dependencies
sudo apt install -y openjdk-17-jdk adb

# activate libvirtd
sudo systemctl enable libvirtd
sudo systemctl status libvirtd
