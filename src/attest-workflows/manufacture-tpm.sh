# SPDX-License-Identifier: Apache-2.0

# Prepare (TPM) Manufacturer public register
# ==========================================

# Initialize Manufacturer Root CA
# -------------------------------
# See https://gist.github.com/op-ct/e202fc911de22c018effdb3371e8335f
# See https://gist.github.com/vszakats/7ef9e86506f5add961bae0412ecbe696

# Config for the Manufacturer's Root CA CSR
cat > manufacturer/ca.cnf <<'EOT'
# OpenSSL CA configuration file
[ ca ]
default_ca = CA_default

[ CA_default ]
default_days = 365
database = ca/index.txt
serial = ca/serial.txt
default_md = sha256
copy_extensions = copy
unique_subject = no

# Used to create the CA certificate.
[ req ]
prompt=no
distinguished_name = distinguished_name
x509_extensions = extensions

[ extensions ]
keyUsage = critical,digitalSignature,nonRepudiation,keyEncipherment,keyCertSign
basicConstraints = critical,CA:true,pathlen:1
#subjectKeyIdentifier = hash

[ distinguished_name ]
O  = TPM Manufacturer
OU = TPM Manufacturer Root CA
CN = TPM Manufacturer Root CA

# Common policy for nodes and users.
[ signing_policy ]
organizationName = supplied
commonName = optional

# Used to sign node certificates.
[ signing_node_req ]
keyUsage = critical,digitalSignature,keyEncipherment
extendedKeyUsage = serverAuth,clientAuth

# Used to sign client certificates.
[ signing_client_req ]
keyUsage = critical,digitalSignature,keyEncipherment
extendedKeyUsage = clientAuth
EOT

# Create the Manufacturer CA key using the openssl genrsa command:
openssl genrsa -out manufacturer/ca.key 2048
chmod 400 manufacturer/ca.key

# Export CA public key
openssl rsa -in manufacturer/ca.key -pubout \
> manufacturer/ca.pub

# Create the Manufacturer CA certificate using the openssl req command:
openssl req \
-new \
-x509 \
-config manufacturer/ca.cnf \
-key manufacturer/ca.key \
-out manufacturer/ca.crt \
-days 365 \
-batch

# export Manufacture CA cert to Verifier
cp manufacturer/ca.crt verifier/ca.crt

# Reset database and index files:
rm -f manufacturer/index.txt manufacturer/serial.txt
touch manufacturer/index.txt
echo '01' > manufacturer/serial.txt

# Config for the Manufacturer's TPM EK CSR
cat > manufacturer/ek.cnf <<'EOT'
openssl_conf = openssl_init

[openssl_init]
oid_section = tpm_oids

[tpm_oids]
TPMManufacturer=tcg_at_tpmManufacturer,2.23.133.2.1
TPMModel=tcg-at-tpmModel,2.23.133.2.2
TPMVersion=tcg-at-tpmVersion,2.23.133.2.3
TPMSpecification=tcg-at-tpmSpecification,2.23.133.2.16

[req]
#prompt = no
default_bits = 2048
encrypt_key = yes
utf8 = yes
string_mask = utf8only
certificatePolicies= 2.23.133.2.1
distinguished_name = req_distinguished_name
req_extensions = v3_req

[req_distinguished_name]

[v3_req]
subjectAltName=critical,ASN1:SEQUENCE:dir_seq
basicConstraints=critical,CA:FALSE
keyUsage = keyEncipherment
[dir_seq]
seq = EXPLICIT:4,SEQUENCE:dir_seq_seq

[dir_seq_seq]
set = SET:dir_set_1

[dir_set_1]
seq.1 = SEQUENCE:dir_seq_1
seq.2 = SEQUENCE:dir_seq_2
seq.3 = SEQUENCE:dir_seq_3

[dir_seq_1]
oid=OID:2.23.133.2.1
str=UTF8:"id:%TPM_MANUFACTURER%"

[dir_seq_2]
oid=OID:2.23.133.2.2
str=UTF8:"id:%TPM_MODEL%"

[dir_seq_3]
oid=OID:2.23.133.2.3
str=UTF8:"id:%TPM_FIRMWARE_VERSION%"

[dir_sect]
O=foo

[foo___sec]
foo.1 = ASN1:OID:"TPMModel"
foo.2 = ASN1:INTEGER:1
EOT

# See https://gist.github.com/op-ct/e202fc911de22c018effdb3371e8335f
#
# Steps:
#
#   - [as input] take a RSA public key (TPM 2.0 public EK)
#   - generate a X.509v3 CSR from the TPM's public EK
#   - [as output] generate and sign an X.509v3 EK Credential certificate
#
# The generated CSR and X.509 certificate contain structures specific to TPM
# 2.0 EK Credentials
#
#   - This includes SOME of the X509v3 extensions expected from a PC Client
#     Platform TPM manufacturer.
#   - This does NOT icomprehensively include all of the guidance documented in
#     "TCG EK Credential Profile for TPM Family 2.0"
#     https://trustedcomputinggroup.org/tcg-ek-credential-profile-tpm-family-2-0/
#
# Generate a signed  X.509 certificate from the TPM's Endorsment key.
#
# A TPM's private Endorsement Key is inaccessible by design, so only the public
# key is available to create a CSR.
#
# Conceptually, that seems straightforward: an X.509 CSR is essentially a public
# key with additional attributes.  However:
#
#   - A private key is still required to sign the CSR.
#   - Most SSL tools (including `openssl req` are hard-coded to simply generate
#     the public key for the CSR directly from that private key.
#
# This involves two workarounds:
#
#   - We create a spurious private key to give to `openssl req` so it will
#     create the CSR
#   - Then we tell `openssl x509` to use our TPM's public key instead
#     with the option `-force_pubkey FILE`.

# Prepare a CSR for EK
# --------------------

openssl genrsa -out manufacturer/trash.key 2048
chmod 400 manufacturer/trash.key

openssl req \
-verbose \
-new \
-subj '/' \
-config manufacturer/ek.cnf \
-key manufacturer/trash.key \
-out manufacturer/ek.csr \
-batch

# Retrieve the instance TPM's EK
# ------------------------------
gcloud compute instances get-shielded-identity $INSTANCE --zone $ZONE \
| yq r - encryptionKey.ekPub \
| grep -v '^[ ]*$' \
> manufacturer/ek.pub

openssl x509 -in manufacturer/ek.csr -req \
  -extfile manufacturer/ek.cnf \
  -force_pubkey manufacturer/ek.pub \
  -CA manufacturer/ca.crt -CAkey manufacturer/ca.key \
  -CAcreateserial \
  -out manufacturer/ek.crt \
  -extensions v3_req \
  -days 365 -sha256

# Config for Manufacturer Root CA CSR