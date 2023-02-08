# Inspired by https://tpm2-software.github.io/2020/06/12/Remote-Attestation-With-tpm2-tools.html#simple-attestation-with-tpm2-tools

# On attester (the machine being onboarded)
# -----------------------------------------

rm -rf machine
mkdir -p machine

tpm2_clear

tpm2_createek \
--ek-context machine/ek.ctx \
--key-algorithm rsa \
--public machine/ek_pub.tss

tpm2_print -t TPM2B_PUBLIC -f pem machine/ek_pub.tss \
> machine/ek_pub.pem

tpm2_createak \
--ek-context machine/ek.ctx \
--ak-context machine/ak.ctx \
--key-algorithm rsa \
--hash-algorithm sha256 \
--signing-algorithm rsassa \
--public machine/ak_pub.tss \
--private machine/ak_priv.tss \
--ak-name machine/ak.name

tpm2_print -t TPM2B_PUBLIC -f pem machine/ak_pub.tss \
> machine/ak_pub.pem

# On verifier (e.g. CI/CD chain)
# ------------------------------

# Verify that the EK is known to the TPM manufacturer
if diff -bB manufacturer/ek_pub_ref.pem machine/ek_pub.pem; then
    echo ek_pub is as expected
else
    echo ek_pub is not as expected from manufacturer records
    (exit 1)
fi   

# Properly format the AK name
file_size=`stat --printf="%s" machine/ak.name`
loaded_key_name=`cat machine/ak.name | xxd -p -c $file_size`

# Create wrapped credential blob
head -c 16 /dev/urandom | xxd -p > machine/challenge.data
tpm2_makecredential \
--tcti none \
--encryption-key machine/ek_pub.tss \
--secret machine/challenge.data \
--name $loaded_key_name \
--credential-blob machine/cred.out

# On attester
# -----------

# Activate the wrapped credential
tpm2_startauthsession \
--policy-session \
--session machine/session.ctx

TPM2_RH_ENDORSEMENT=0x4000000B
tpm2_policysecret -S machine/session.ctx -c $TPM2_RH_ENDORSEMENT

tpm2_activatecredential \
--credentialedkey-context machine/ak.ctx \
--credentialkey-context machine/ek.ctx \
--credential-blob machine/cred.out \
--certinfo-data machine/actcred.out \
--credentialkey-auth "session:machine/session.ctx"

# tpm2_flushcontext machine/session.ctx
tpm2_evictcontrol -c machine/ak.ctx 0x81000000

# On verifier
# -----------

if diff -q machine/challenge.data machine/actcred.out >/dev/null; then
  echo Credential activation succeeded
else
  echo Credential activation failed!
  (exit 1)
fi

###
### At this point verifier knows that TPM is legit
###

# On verifier
# -----------

# Create nonce
head -c 16 /dev/urandom | xxd -p > machine/quote_nonce.data

# On attester
# -----------
tpm2_quote \
--key-context machine/ak.ctx \
--pcr-list sha256:0,1,2,3,4,5,6,7,8,9,14 \
--message machine/pcr_quote.plain \
--signature machine/pcr_quote.signature \
--qualification machine/quote_nonce.data \
--hash-algorithm sha256

# On verifier
# -----------

# Check quote is legit
if tpm2_checkquote \
--public machine/ak_pub.tss \
--message machine/pcr_quote.plain \
--signature machine/pcr_quote.signature \
--qualification machine/quote_nonce.data; then
    echo Quote verification succeeded
else
    echo Quote verification failed!
    (exit 1)
fi

# Check PCR values are OK
cat machine/pcr_quote.plain \
| xxd -p -c 0 -g 0 \
| tail -c 65 \
> machine/actual_digest.txt

if diff machine/actual_digest.txt image/expected_digest.txt; then
    echo Machine integrity check succeeded
else
    echo Machine integrity check failed!
    (exit 1)
fi

###
### At this point verifier knows that machine state has integrity
###


# Now we create a certificate for Endorsement-Hierarchy's AK


# On verifier
# -----------

# Create the ak.cnf file for AK:
rm -rf certs
mkdir -p certs

cat > certs/ak.cnf <<'EOT'
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

# Create the CSR for AK using the openssl req command:
# See https://github.com/tpm2-software/tpm2-openssl/blob/master/docs/certificates.md
openssl req \
-provider tpm2 \
-new \
-config certs/ak.cnf \
-key handle:0x81000000 \
-out certs/ak.csr \
-batch

# Sign the client CSR to create the client certificate for the first client using the openssl ca command.
openssl ca \
-config ca/ca.cnf \
-keyfile ca/ca.key \
-cert ca/ca.crt \
-policy signing_policy \
-extensions signing_client_req \
-out certs/ak.crt \
-outdir certs/ \
-in certs/ak.csr \
-batch

# Verify the values in the CN field in the certificate:
openssl x509 -in certs/ak.crt -text | grep "CN ="

# TODO
# Let machine create Owner-Hierarchy SRK and AIK
# Let verifier/CA record SRK and AIK public keys
# Let CA create certificate for AIK

# TODO2
# Remote attestation using AIK

# TODO3
# Seal + Unseal secret

# TODO4
# Add check that CC is enabled