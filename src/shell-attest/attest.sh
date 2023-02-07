# Inspired by https://tpm2-software.github.io/2020/06/12/Remote-Attestation-With-tpm2-tools.html#simple-attestation-with-tpm2-tools

# Attester machine configuration
# ------------------------------

# Install TPM2 provider for openssl
sudo apt-get install tpm2-openssl


# On attester (the machine being onboarded)
# -----------------------------------------

tpm2_createek \
--ek-context rsa_ek.ctx \
--key-algorithm rsa \
--public rsa_ek.pub

tpm2_createak \
--ek-context rsa_ek.ctx \
--ak-context rsa_ak.ctx \
--key-algorithm rsa \
--hash-algorithm sha256 \
--signing-algorithm rsassa \
--public rsa_ak.pub \
--private rsa_ak.priv \
--ak-name rsa_ak.name

# On verifier (e.g. CI/CD chain)
# ------------------------------

# Verify that the EK is known to the TPM manufacturer
# TODO

# Properly format the AK name
file_size=`stat --printf="%s" rsa_ak.name`
loaded_key_name=`cat rsa_ak.name | xxd -p -c $file_size`

# Create wrapped credential blob
head -c 16 /dev/urandom | xxd -p > file_input.data
tpm2_makecredential \
--tcti none \
--encryption-key rsa_ek.pub \
--secret file_input.data \
--name $loaded_key_name \
--credential-blob cred.out

# On attester
# -----------

# Activate the wrapped credential
tpm2_startauthsession \
--policy-session \
--session session.ctx

TPM2_RH_ENDORSEMENT=0x4000000B
tpm2_policysecret -S session.ctx -c $TPM2_RH_ENDORSEMENT

tpm2_activatecredential \
--credentialedkey-context rsa_ak.ctx \
--credentialkey-context rsa_ek.ctx \
--credential-blob cred.out \
--certinfo-data actcred.out \
--credentialkey-auth "session:session.ctx"

tpm2_flushcontext session.ctx

if diff -q file_input.data actcred.out >/dev/null; then
  echo Credential activation succeeded
else
  echo Credential activation failed!
fi

# At time of CA key ceremony
# --------------------------

# Inspired by https://www.cockroachlabs.com/docs/stable/create-security-certificates-openssl.html

# Generate private key and self-signed certificate for CA
# (In prod, private key must remain in HSM)

cat > ca.cnf <<'EOT'
# OpenSSL CA configuration file
[ ca ]
default_ca = CA_default

[ CA_default ]
default_days = 365
database = index.txt
serial = serial.txt
default_md = sha256
copy_extensions = copy
unique_subject = no

# Used to create the CA certificate.
[ req ]
prompt=no
distinguished_name = distinguished_name
x509_extensions = extensions

[ distinguished_name ]
organizationName = S3NS
commonName = S3NS CA

[ extensions ]
keyUsage = critical,digitalSignature,nonRepudiation,keyEncipherment,keyCertSign
basicConstraints = critical,CA:true,pathlen:1

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

# Create the CA key using the openssl genrsa command:
openssl genrsa -out ca.key 2048
chmod 400 ca.key

# Create the CA certificate using the openssl req command:
openssl req \
-new \
-x509 \
-config ca.cnf \
-key ca.key \
-out ca.crt \
-days 365 \
-batch

# Reset database and index files:
rm -f index.txt serial.txt
touch index.txt
echo '01' > serial.txt

# Create the client.cnf file for the first user and copy the following configuration into it:

cat > client.cnf <<'EOT'
[ req ]
prompt=no
distinguished_name = distinguished_name
req_extensions = extensions

[ distinguished_name ]
organizationName = S3NS
commonName = AK

[ extensions ]
subjectAltName = DNS:root
EOT

# Create the key for the first client using the openssl genrsa command:
##openssl genrsa -out certs/client.AK.key 2048
##chmod 400 certs/client.AK.key

# Create the CSR for the first client using the openssl req command:
# https://github.com/tpm2-software/tpm2-openssl/blob/master/docs/certificates.md
tpm2_evictcontrol -c rsa_ak.ctx 0x81000000
openssl req \
-provider tpm2 \
-new \
-config client.cnf \
-key handle:0x81000000 \
-out client.AK.csr \
-batch


# Sign the client CSR to create the client certificate for the first client using the openssl ca command.
openssl ca \
-config ca.cnf \
-keyfile ca.key \
-cert ca.crt \
-policy signing_policy \
-extensions signing_client_req \
-out client.AK.crt \
-outdir certs/ \
-in client.AK.csr \
-batch

# Verify the values in the CN field in the certificate:
openssl x509 -in certs/client.AK.crt -text | grep CN=




# Create a CSR for the AK
# Have S3NS CA sign the CSR

# Same for the AIK