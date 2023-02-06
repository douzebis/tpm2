package main

import (
	"encoding/pem"
	"glog"
	"io/ioutil"
	"os"

	"flag"

	"crypto/x509"

	"github.com/google/go-tpm/tpm2"
)

var (
	tpmPath = flag.String("tpm-path", "/dev/tpmrm0", "Path to the TPM device (character device or a Unix socket).")
)

func main() {
	flag.Parse()
	glog.V(2).Infof("tmpPath is: %s", *tpmPath)

	f, err := os.OpenFile("/dev/tpmrm0", os.O_RDWR, 0)
	if err != nil {
		glog.Fatalf("opening tpm: %v", err)
	}
	defer f.Close()

	tmpl := tpm2.Public{
		Type:    tpm2.AlgRSA,
		NameAlg: tpm2.AlgSHA256,
		Attributes: tpm2.FlagFixedTPM | // Key can't leave the TPM.
			tpm2.FlagFixedParent | // Key can't change parent.
			tpm2.FlagSensitiveDataOrigin | // Key created by the TPM (not imported).
			tpm2.FlagAdminWithPolicy | // Key has an authPolicy.
			tpm2.FlagRestricted | // Key used for TPM challenges, not general decryption.
			tpm2.FlagDecrypt, // Key can be used to decrypt data.
		AuthPolicy: []byte{
			// TPM2_PolicySecret(TPM_RH_ENDORSEMENT)
			// Endorsement hierarchy must be unlocked to use this key.
			0x83, 0x71, 0x97, 0x67, 0x44, 0x84,
			0xB3, 0xF8, 0x1A, 0x90, 0xCC, 0x8D,
			0x46, 0xA5, 0xD7, 0x24, 0xFD, 0x52,
			0xD7, 0x6E, 0x06, 0x52, 0x0B, 0x64,
			0xF2, 0xA1, 0xDA, 0x1B, 0x33, 0x14,
			0x69, 0xAA,
		},
		RSAParameters: &tpm2.RSAParams{
			Symmetric:  &tpm2.SymScheme{Alg: tpm2.AlgAES, KeyBits: 128, Mode: tpm2.AlgCFB},
			KeyBits:    2048,
			ModulusRaw: make([]byte, 256),
		},
	}

	ek, pub, err := tpm2.CreatePrimary(f, tpm2.HandleEndorsement, tpm2.PCRSelection{}, "", "", tmpl)
	if err != nil {
		glog.Fatalf("creating ek: %v", err)
	}
	out, err := tpm2.ContextSave(f, ek)
	if err != nil {
		glog.Fatalf("saving context: %v", err)
	}
	if err := ioutil.WriteFile("ek.ctx", out, 0644); err != nil {
		glog.Fatalf("writing context: %v", err)
	}

	pubDER, err := x509.MarshalPKIXPublicKey(pub)
	if err != nil {
		glog.Fatalf("encoding public key: %v", err)
	}
	b := &pem.Block{Type: "PUBLIC KEY", Bytes: pubDER}
	pem.Encode(os.Stdout, b)
}
