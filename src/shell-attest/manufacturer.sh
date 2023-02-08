# Manufacturer public register
# ----------------------------

rm -rf manufacturer
mkdir -p manufacturer

# Install yq yaml parser
# See https://mikefarah.gitbook.io/yq/v/v3.x/
sudo snap install yq --channel=v3/stable

gcloud auth login
gcloud compute instances get-shielded-identity tpm1 --zone europe-west9-b \
| yq r - encryptionKey.ekPub \
> manufacturer/ek_pub_ref.pem
