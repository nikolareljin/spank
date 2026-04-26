//go:build linux

package sensor

import (
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

type AlternativeSensor struct {
	ID     string
	Name   string
	Path   string
	Reason string
}

type alternativeRoots struct {
	accelClass string
	inputClass string
}

func ExplainDiscoveryFailure(err error) error {
	if err == nil {
		return nil
	}

	alternatives := discoverAlternativeSensors(alternativeRoots{
		accelClass: "/sys/class/accel",
		inputClass: "/sys/class/input",
	})
	if len(alternatives) == 0 {
		return err
	}

	return fmt.Errorf("%w; unsupported related sensors detected: %s", err, formatAlternativeSensors(alternatives))
}

func discoverAlternativeSensors(roots alternativeRoots) []AlternativeSensor {
	var sensors []AlternativeSensor

	sensors = append(sensors, discoverAccelClassSensors(roots.accelClass)...)
	sensors = append(sensors, discoverInputClassSensors(roots.inputClass)...)

	sort.SliceStable(sensors, func(i, j int) bool {
		if sensors[i].Name == sensors[j].Name {
			return sensors[i].Path < sensors[j].Path
		}
		return sensors[i].Name < sensors[j].Name
	})
	return sensors
}

func discoverAccelClassSensors(root string) []AlternativeSensor {
	entries, err := os.ReadDir(root)
	if err != nil {
		return nil
	}

	var sensors []AlternativeSensor
	for _, entry := range entries {
		path := filepath.Join(root, entry.Name())
		realPath, _ := filepath.EvalSymlinks(path)
		if realPath == "" {
			realPath = path
		}
		sensors = append(sensors, AlternativeSensor{
			ID:     entry.Name(),
			Name:   entry.Name(),
			Path:   realPath,
			Reason: "/sys/class/accel entry found, but spank currently reads raw XYZ data from Linux IIO only",
		})
	}
	return sensors
}

func discoverInputClassSensors(root string) []AlternativeSensor {
	events, err := filepath.Glob(filepath.Join(root, "event*"))
	if err != nil {
		return nil
	}

	var sensors []AlternativeSensor
	for _, event := range events {
		name := readTrim(filepath.Join(event, "device", "name"))
		devicePath, _ := filepath.EvalSymlinks(filepath.Join(event, "device"))
		lower := strings.ToLower(name + " " + devicePath)

		reason := ""
		switch {
		case strings.Contains(lower, "lid"):
			reason = "switch-style sensor; reports lid open/close state instead of raw XYZ acceleration"
		case containsAny(lower, "accel", "gyro", "motion", "sensor", "inclin"):
			reason = "input event sensor; spank currently supports raw Linux IIO accelerometers only"
		default:
			continue
		}

		if devicePath == "" {
			devicePath = filepath.Join(event, "device")
		}
		sensors = append(sensors, AlternativeSensor{
			ID:     filepath.Base(event),
			Name:   name,
			Path:   devicePath,
			Reason: reason,
		})
	}
	return sensors
}

func formatAlternativeSensors(sensors []AlternativeSensor) string {
	const maxItems = 3

	items := make([]string, 0, min(len(sensors), maxItems))
	for i, sensor := range sensors {
		if i == maxItems {
			break
		}
		label := sensor.Name
		if strings.TrimSpace(label) == "" {
			label = sensor.ID
		}
		items = append(items, fmt.Sprintf("%s (%s: %s)", label, sensor.Path, sensor.Reason))
	}
	if len(sensors) > maxItems {
		items = append(items, fmt.Sprintf("%d more omitted", len(sensors)-maxItems))
	}
	return strings.Join(items, "; ")
}

func containsAny(value string, needles ...string) bool {
	for _, needle := range needles {
		if strings.Contains(value, needle) {
			return true
		}
	}
	return false
}
