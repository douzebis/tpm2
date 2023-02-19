# SPDX-License-Identifier: Apache-2.0

# Retrieve EK Pub from TPM and match with Manufacturer cert
# =========================================================

# Power up Attestor with Registration boot image

# <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
# On attestor
# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>

tpm2_clear

# Create EK with default template
tpm2_createek \
--ek-context attestor/ek.ctx \
--key-algorithm rsa \
--public attestor/ek.tss

# Retrieve EK public key
tpm2_print -t TPM2B_PUBLIC -f pem attestor/ek.tss \
> attestor/ek.pub

# Send EK public key to Verifier
cp attestor/ek.pub verifier/ek.pub


# <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
# On verifier
# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>

# Retrieve Manufacturer registry
cp manufacturer/ek.crt verifier/ek-ref.crt

# Assess retrieved Manufacturer assets are legit
if openssl verify -verbose -CAfile verifier/ca.crt verifier/ca.crt; then
    echo -e ${GREEN}Manufacturer CA cert is OK${NC}
else
    echo -e ${ORANGE}Manufacturer CA cert has problems${NC}
    (exit 1)
fi

if openssl verify -verbose -CAfile verifier/ca.crt verifier/ek-ref.crt; then
    echo -e ${GREEN}Manufacturer TPM cert is OK${NC}
else
    echo -e ${ORANGE}Manufacturer TPM cert has problems${NC}
    (exit 1)
fi

# Find EK in Manufacturer registry
openssl x509 -in verifier/ek-ref.crt -pubkey -noout \
> verifier/ek-ref.pub
if diff verifier/ek.pub verifier/ek-ref.pub; then
    echo -e ${GREEN}found ek.pub in Manufacturer registry${NC}
else
    echo -e ${ORANGE}could not find ek.pub in Manufacturer registry${NC}
    (exit 1)
fi
