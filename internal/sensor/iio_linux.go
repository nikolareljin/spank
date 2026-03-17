//go:build linux

package sensor

import (
	"context"
	"errors"
	"fmt"
	"math"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"time"
)

type IIOProvider struct {
	SysfsRoot string
	DmiRoot   string
}

func NewIIOProvider(sysfsRoot, dmiRoot string) *IIOProvider {
	return &IIOProvider{SysfsRoot: sysfsRoot, DmiRoot: dmiRoot}
}

func (p *IIOProvider) Discover(_ context.Context) ([]SensorInfo, error) {
	entries, err := os.ReadDir(p.SysfsRoot)
	if err != nil {
		return nil, fmt.Errorf("read sysfs root %s: %w", p.SysfsRoot, err)
	}

	vendor := strings.ToLower(readTrim(filepath.Join(p.DmiRoot, "sys_vendor")))
	product := strings.ToLower(readTrim(filepath.Join(p.DmiRoot, "product_name")))

	type ranked struct {
		info  SensorInfo
		score int
	}
	var rankedSensors []ranked
	for _, entry := range entries {
		if !entry.IsDir() || !strings.HasPrefix(entry.Name(), "iio:device") {
			continue
		}
		path := filepath.Join(p.SysfsRoot, entry.Name())
		info, score, ok := probeDevice(path, vendor, product)
		if !ok {
			continue
		}
		rankedSensors = append(rankedSensors, ranked{info: info, score: score})
	}

	sort.SliceStable(rankedSensors, func(i, j int) bool {
		if rankedSensors[i].score == rankedSensors[j].score {
			return rankedSensors[i].info.Path < rankedSensors[j].info.Path
		}
		return rankedSensors[i].score > rankedSensors[j].score
	})

	result := make([]SensorInfo, 0, len(rankedSensors))
	for _, candidate := range rankedSensors {
		result = append(result, candidate.info)
	}
	return result, nil
}

func (p *IIOProvider) Open(_ context.Context, info SensorInfo, _ time.Duration) (Stream, error) {
	if info.Path == "" {
		return nil, errors.New("sensor path is required")
	}
	return &iioStream{info: info}, nil
}

type iioStream struct {
	info SensorInfo
}

func (s *iioStream) Read(_ context.Context) (Sample, error) {
	x, err := readAxis(filepath.Join(s.info.Path, "in_accel_x_raw"), s.info.Scale)
	if err != nil {
		return Sample{}, err
	}
	y, err := readAxis(filepath.Join(s.info.Path, "in_accel_y_raw"), s.info.Scale)
	if err != nil {
		return Sample{}, err
	}
	z, err := readAxis(filepath.Join(s.info.Path, "in_accel_z_raw"), s.info.Scale)
	if err != nil {
		return Sample{}, err
	}

	mag := math.Sqrt(x*x + y*y + z*z)
	return Sample{
		Timestamp: time.Now(),
		X:         x,
		Y:         y,
		Z:         z,
		Magnitude: mag,
		Unit:      "m/s^2",
	}, nil
}

func FindSensor(ctx context.Context, provider Provider, override string) (SensorInfo, error) {
	sensors, err := provider.Discover(ctx)
	if err != nil {
		return SensorInfo{}, err
	}
	if len(sensors) == 0 {
		return SensorInfo{}, errors.New("no compatible Linux IIO accelerometer found")
	}
	if override == "" {
		return sensors[0], nil
	}
	for _, info := range sensors {
		if info.Path == override || info.Name == override || info.ID == override {
			return info, nil
		}
	}

	path := override
	if st, err := os.Stat(path); err == nil && st.IsDir() {
		info, _, ok := probeDevice(path, "", "")
		if ok {
			return info, nil
		}
	}
	return SensorInfo{}, fmt.Errorf("sensor override %q not found among discovered accelerometers", override)
}

func probeDevice(path, vendor, product string) (SensorInfo, int, bool) {
	required := []string{
		filepath.Join(path, "in_accel_x_raw"),
		filepath.Join(path, "in_accel_y_raw"),
		filepath.Join(path, "in_accel_z_raw"),
	}
	for _, item := range required {
		if _, err := os.Stat(item); err != nil {
			return SensorInfo{}, 0, false
		}
	}

	scale, err := readFloatPrefer(path, []string{"in_accel_scale", "scale"})
	if err != nil || scale == 0 {
		scale = 1
	}

	name := readTrim(filepath.Join(path, "name"))
	label := readTrim(filepath.Join(path, "label"))
	location := readTrim(filepath.Join(path, "location"))
	if location == "" {
		location = readTrim(filepath.Join(path, "mount_matrix"))
	}
	rate := firstNonEmpty(
		readTrim(filepath.Join(path, "sampling_frequency")),
		readTrim(filepath.Join(path, "in_accel_sampling_frequency")),
		readTrim(filepath.Join(path, "in_accel_sampling_frequency_available")),
	)

	score := 100
	reasons := []string{"3-axis accelerometer present"}
	lowerName := strings.ToLower(name + " " + label)
	if strings.Contains(lowerName, "accel") {
		score += 20
		reasons = append(reasons, "accelerometer naming")
	}
	if strings.Contains(lowerName, "hid-sensor") || strings.Contains(lowerName, "iio") {
		score += 10
		reasons = append(reasons, "IIO/HID sensor naming")
	}
	lowerLocation := strings.ToLower(location)
	if strings.Contains(lowerLocation, "base") || strings.Contains(lowerLocation, "chassis") || strings.Contains(lowerLocation, "lid") {
		score += 8
		reasons = append(reasons, "laptop location metadata")
	}
	if strings.Contains(vendor, "lenovo") || strings.Contains(product, "thinkpad") || strings.Contains(product, "yoga") {
		score += 6
		reasons = append(reasons, "Lenovo-targeted DMI hint")
	}

	id := filepath.Base(path)
	return SensorInfo{
		ID:         id,
		Path:       path,
		Name:       name,
		Label:      label,
		Location:   location,
		Scale:      scale,
		SampleRate: rate,
		RankReason: strings.Join(reasons, ", "),
	}, score, true
}

func readAxis(path string, scale float64) (float64, error) {
	v, err := readInt(path)
	if err != nil {
		return 0, err
	}
	return float64(v) * scale, nil
}

func readInt(path string) (int64, error) {
	s := readTrim(path)
	if s == "" {
		return 0, fmt.Errorf("read %s: empty value", path)
	}
	v, err := strconv.ParseInt(s, 10, 64)
	if err != nil {
		return 0, fmt.Errorf("parse %s: %w", path, err)
	}
	return v, nil
}

func readFloatPrefer(base string, names []string) (float64, error) {
	for _, name := range names {
		path := filepath.Join(base, name)
		s := readTrim(path)
		if s == "" {
			continue
		}
		v, err := strconv.ParseFloat(s, 64)
		if err != nil {
			return 0, fmt.Errorf("parse %s: %w", path, err)
		}
		return v, nil
	}
	return 0, errors.New("scale not found")
}

func readTrim(path string) string {
	data, err := os.ReadFile(path)
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(data))
}

func firstNonEmpty(values ...string) string {
	for _, value := range values {
		if value != "" {
			return value
		}
	}
	return ""
}
