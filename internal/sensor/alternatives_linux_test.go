//go:build linux

package sensor

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestDiscoverAlternativeSensorsFindsLidSwitch(t *testing.T) {
	root := t.TempDir()
	inputClass := filepath.Join(root, "input")
	if err := os.MkdirAll(filepath.Join(inputClass, "event1", "device"), 0o755); err != nil {
		t.Fatal(err)
	}

	writeFile(t, filepath.Join(inputClass, "event1", "device", "name"), "Lid Switch")

	sensors := discoverAlternativeSensors(alternativeRoots{
		accelClass: filepath.Join(root, "accel"),
		inputClass: inputClass,
	})
	if len(sensors) != 1 {
		t.Fatalf("expected 1 alternative sensor, got %d", len(sensors))
	}
	if sensors[0].ID != "event1" {
		t.Fatalf("id = %q", sensors[0].ID)
	}
	if !strings.Contains(strings.ToLower(sensors[0].Reason), "lid open/close") {
		t.Fatalf("reason = %q", sensors[0].Reason)
	}
}

func TestFormatAlternativeSensorsLimitsOutput(t *testing.T) {
	got := formatAlternativeSensors([]AlternativeSensor{
		{Name: "A", Path: "/a", Reason: "one"},
		{Name: "B", Path: "/b", Reason: "two"},
		{Name: "C", Path: "/c", Reason: "three"},
		{Name: "D", Path: "/d", Reason: "four"},
	})
	if !strings.Contains(got, "1 more omitted") {
		t.Fatalf("formatted output = %q", got)
	}
}
