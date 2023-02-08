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
# See https://google.github.io/tpm-js/#pg_pcrs

rm -rf image
mkdir -p image
sudo tpm2_eventlog /sys/kernel/security/tpm0/binary_bios_measurements \
> image/eventlog.txt

for ndx in 0 1 2 3 4 5 6 7 8 9 14; do
    tpm2_pcrread -o image/pcr$ndx.bin sha256:$ndx
done
cat image/pcr[0123456789].bin image/pcr14.bin \
| openssl dgst -sha256 -binary \
| xxd -p -c 32 -g 32 \
> image/expected_digest.txt
