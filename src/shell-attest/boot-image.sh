# Boot image configuration
# ------------------------

# In prod, this has to be performed by the CI/CD that builds
# the boot image for the machines of the fleet.

sudo apt-get update

# Install tpm2-tools
sudo apt-get install tpm2-tools

# Install TPM2 provider for openssl
sudo apt-get install tpm2-openssl

# Give ubuntu user access to tpm device
# See https://superuser.com/a/1505618 for a potentially better way
usermod -a -G tss ubuntu
exit 0

# Install Golang
sudo apt-get install golang-go

# Put image in a deterministic repeatable state
sudo update-grub
sudo reboot now

# Predict PCR status
# TODO
sudo tpm2_pcrread
