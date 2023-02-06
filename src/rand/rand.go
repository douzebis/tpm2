package main

import (
	"os"

	"flag"

	"github.com/golang/glog"
	"github.com/google/go-tpm/tpm2"
)

var (
	tpmPath = flag.String("tpm-path", "/dev/tpmrm0", "Path to the TPM device (character device or a Unix socket).")
)

func main() {
	flag.Parse()
	glog.V(2).Infof("tmpPath is: %s", *tpmPath)

	f, err := os.OpenFile(*tpmPath, os.O_RDWR, 0)
	if err != nil {
		glog.Fatalf("opening tpm: %v", err)
	}
	defer f.Close()

	out, err := tpm2.GetRandom(f, 16)
	if err != nil {
		glog.Fatalf("getting random bytes: %v", err)
	}
	glog.V(2).Infof("random bytes are: %x\n", out)
}
