# At time of CA key ceremony
# --------------------------

# Inspired by https://www.cockroachlabs.com/docs/stable/create-security-certificates-openssl.html

# Generate private key and self-signed certificate for CA
# (In prod, this must be done using an HSM and the
# CA private key must remain in the HSM)

rm -rf ca
mkdir -p ca
cat > ca/ca.cnf <<'EOT'
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
openssl genrsa -out ca/ca.key 2048
chmod 400 ca/ca.key

# Create the CA certificate using the openssl req command:
openssl req \
-new \
-x509 \
-config ca/ca.cnf \
-key ca/ca.key \
-out ca/ca.crt \
-days 365 \
-batch

# Reset database and index files:
rm -f ca/index.txt ca/serial.txt
touch ca/index.txt
echo '01' > ca/serial.txt
