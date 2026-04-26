//go:build linux

package sensor

import (
	"path/filepath"
	"strings"
	"testing"
)

func TestDiscoveryAdviceIncludesThinkPadT14Gen1Guidance(t *testing.T) {
	root := t.TempDir()
	writeFile(t, filepath.Join(root, "sys_vendor"), "LENOVO")
	writeFile(t, filepath.Join(root, "product_name"), "20UD000CUS")
	writeFile(t, filepath.Join(root, "product_version"), "ThinkPad T14 Gen 1")

	advice := strings.Join(DiscoveryAdvice(root), "\n")
	if !strings.Contains(advice, "T14 Gen 1 AMD Lenovo spec sheet does not advertise one") {
		t.Fatalf("advice = %q", advice)
	}
	if !strings.Contains(advice, "machine type 20UD") {
		t.Fatalf("advice = %q", advice)
	}
}
