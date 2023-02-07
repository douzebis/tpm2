# Inspired by https://tpm2-software.github.io/2020/06/12/Remote-Attestation-With-tpm2-tools.html#simple-attestation-with-tpm2-tools

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


# Create a CSR signed by the AK, for the EK
# - Subject is AK
# - Common name is EK?
# Have S3NS CA sign the CSR