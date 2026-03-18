//go:build linux

package sensor

import (
	"path/filepath"
	"strings"
)

func DiscoveryAdvice(dmiRoot string) []string {
	advice := []string{
		"verify the kernel exposes accelerometers under /sys/bus/iio/devices",
		"check kernel logs with: journalctl -k -b | rg 'iio|sensor|accel|gyro|hid'",
		"try loading sensor modules: sudo modprobe industrialio hid_sensor_hub hid_sensor_accel_3d hid_sensor_gyro_3d",
		"if no iio:device entries appear after that, the laptop may not expose a Linux-readable accelerometer",
	}

	vendor := strings.ToLower(readTrim(filepath.Join(dmiRoot, "sys_vendor")))
	productName := strings.ToLower(readTrim(filepath.Join(dmiRoot, "product_name")))
	productVersion := strings.ToLower(readTrim(filepath.Join(dmiRoot, "product_version")))

	if vendor == "lenovo" && strings.Contains(productVersion, "thinkpad t14 gen 1") {
		advice = append(advice,
			"ThinkPad T14 Gen 1 systems can ship without a Linux-visible accelerometer; the T14 Gen 1 AMD Lenovo spec sheet does not advertise one, so this may be a platform limitation rather than a spank bug",
		)
	}
	if vendor == "lenovo" && strings.HasPrefix(productName, "20ud") {
		advice = append(advice,
			"machine type 20UD is a T14 Gen 1 AMD family code; if Windows and BIOS also show no motion sensor, treat this machine as unsupported hardware for spank",
		)
	}

	return advice
}

