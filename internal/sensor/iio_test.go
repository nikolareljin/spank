package sensor

import (
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestDiscoverReportsMissingSysfsRootClearly(t *testing.T) {
	root := t.TempDir()
	sysfs := filepath.Join(root, "missing")
	dmi := filepath.Join(root, "dmi")

	provider := NewIIOProvider(sysfs, dmi)
	_, err := provider.Discover(context.Background())
	if err == nil {
		t.Fatal("expected error")
	}
	if !strings.Contains(err.Error(), "does not expose accelerometers") {
		t.Fatalf("unexpected error: %v", err)
	}
}

func TestDiscoverRanksLenovoCandidateFirst(t *testing.T) {
	root := t.TempDir()
	sysfs := filepath.Join(root, "sys", "bus", "iio", "devices")
	dmi := filepath.Join(root, "sys", "class", "dmi", "id")
	if err := os.MkdirAll(sysfs, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(dmi, 0o755); err != nil {
		t.Fatal(err)
	}
	writeFile(t, filepath.Join(dmi, "sys_vendor"), "LENOVO")
	writeFile(t, filepath.Join(dmi, "product_name"), "ThinkPad X1 Yoga")

	makeSensorFixture(t, filepath.Join(sysfs, "iio:device0"), map[string]string{
		"name":               "hid-sensor-accel-3d",
		"label":              "base_accel",
		"location":           "base",
		"in_accel_x_raw":     "1",
		"in_accel_y_raw":     "2",
		"in_accel_z_raw":     "3",
		"in_accel_scale":     "0.01",
		"sampling_frequency": "20",
	})
	makeSensorFixture(t, filepath.Join(sysfs, "iio:device1"), map[string]string{
		"name":           "generic-gyro",
		"in_accel_x_raw": "1",
		"in_accel_y_raw": "2",
		"in_accel_z_raw": "3",
		"in_accel_scale": "0.01",
	})

	provider := NewIIOProvider(sysfs, dmi)
	sensors, err := provider.Discover(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if len(sensors) != 2 {
		t.Fatalf("expected 2 sensors, got %d", len(sensors))
	}
	if sensors[0].Path != filepath.Join(sysfs, "iio:device0") {
		t.Fatalf("unexpected top sensor %s", sensors[0].Path)
	}
	if !strings.Contains(strings.ToLower(sensors[0].RankReason), "lenovo") {
		t.Fatalf("rank reason = %q", sensors[0].RankReason)
	}
}

func TestFindSensorSupportsOverride(t *testing.T) {
	root := t.TempDir()
	sysfs := filepath.Join(root, "devices")
	if err := os.MkdirAll(sysfs, 0o755); err != nil {
		t.Fatal(err)
	}
	makeSensorFixture(t, filepath.Join(sysfs, "iio:device7"), map[string]string{
		"name":           "hid-sensor-accel-3d",
		"in_accel_x_raw": "1",
		"in_accel_y_raw": "2",
		"in_accel_z_raw": "3",
		"in_accel_scale": "0.01",
	})

	provider := NewIIOProvider(sysfs, filepath.Join(root, "dmi"))
	info, err := FindSensor(context.Background(), provider, "iio:device7")
	if err != nil {
		t.Fatal(err)
	}
	if info.ID != "iio:device7" {
		t.Fatalf("id = %q", info.ID)
	}
}

func makeSensorFixture(t *testing.T, path string, files map[string]string) {
	t.Helper()
	if err := os.MkdirAll(path, 0o755); err != nil {
		t.Fatal(err)
	}
	for name, value := range files {
		writeFile(t, filepath.Join(path, name), value)
	}
}

func writeFile(t *testing.T, path, value string) {
	t.Helper()
	if err := os.WriteFile(path, []byte(value+"\n"), 0o644); err != nil {
		t.Fatal(err)
	}
}
