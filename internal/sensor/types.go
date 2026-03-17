package sensor

import (
	"context"
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

type SensorInfo struct {
	ID         string
	Path       string
	Name       string
	Label      string
	Location   string
	Scale      float64
	SampleRate string
	RankReason string
}

type Provider interface {
	Discover(context.Context) ([]SensorInfo, error)
	Open(context.Context, SensorInfo, time.Duration) (Stream, error)
}

type Stream interface {
	Read(context.Context) (Sample, error)
}
