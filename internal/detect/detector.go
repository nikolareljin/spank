package detect

import (
	"math"
	"time"
)

type Sample struct {
	Timestamp time.Time
	X         float64
	Y         float64
	Z         float64
	Magnitude float64
	Unit      string
}

type Event struct {
	Timestamp time.Time
	Severity  float64
	Delta     float64
	SensorID  string
}

type Detector struct {
	threshold float64
	cooldown  time.Duration
	alpha     float64
	lastEvent time.Time
	baseline  float64
	ready     bool
}

func New(threshold float64, cooldown time.Duration) *Detector {
	return &Detector{
		threshold: threshold,
		cooldown:  cooldown,
		alpha:     0.18,
	}
}

func (d *Detector) Process(sensorID string, sample Sample) (Event, bool) {
	mag := sample.Magnitude
	if mag == 0 {
		mag = magnitude(sample.X, sample.Y, sample.Z)
	}

	if !d.ready {
		d.baseline = mag
		d.ready = true
		return Event{}, false
	}

	d.baseline = d.alpha*mag + (1-d.alpha)*d.baseline
	delta := math.Abs(mag - d.baseline)
	if delta < d.threshold {
		return Event{}, false
	}
	if !d.lastEvent.IsZero() && sample.Timestamp.Sub(d.lastEvent) < d.cooldown {
		return Event{}, false
	}

	d.lastEvent = sample.Timestamp
	return Event{
		Timestamp: sample.Timestamp,
		Severity:  delta / d.threshold,
		Delta:     delta,
		SensorID:  sensorID,
	}, true
}

func magnitude(x, y, z float64) float64 {
	return math.Sqrt(x*x + y*y + z*z)
}
