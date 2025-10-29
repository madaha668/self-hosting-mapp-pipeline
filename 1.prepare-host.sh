# Update system and install essential tools
sudo apt update && sudo apt upgrade -y
sudo apt install -y curl git wget unzip build-essential cpu-checker

# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER

# Install Docker Compose v2
sudo apt install -y docker-compose-plugin

# Verify and enable KVM for Android emulation
sudo apt install -y qemu-kvm libvirt-daemon-system libvirt-clients bridge-utils
sudo adduser $USER kvm
sudo adduser $USER libvirt
kvm-ok  # Should return "KVM acceleration can be used"

# Install Android emulator dependencies
sudo apt install -y openjdk-17-jdk adb
