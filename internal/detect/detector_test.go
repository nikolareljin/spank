package detect

import (
	"testing"
	"time"
)

func TestDetectorIgnoresIdleNoise(t *testing.T) {
	d := New(1.5, time.Second)
	now := time.Now()
	samples := []Sample{
		{Timestamp: now, X: 0, Y: 0, Z: 1},
		{Timestamp: now.Add(40 * time.Millisecond), X: 0.02, Y: 0.01, Z: 1.01},
		{Timestamp: now.Add(80 * time.Millisecond), X: 0.01, Y: -0.01, Z: 0.99},
	}
	for _, s := range samples {
		if _, ok := d.Process("sensor0", s); ok {
			t.Fatal("idle noise should not trigger")
		}
	}
}

func TestDetectorTriggersOnSharpMotion(t *testing.T) {
	d := New(1.0, time.Second)
	now := time.Now()
	d.Process("sensor0", Sample{Timestamp: now, X: 0, Y: 0, Z: 1})

	event, ok := d.Process("sensor0", Sample{Timestamp: now.Add(50 * time.Millisecond), X: 2.5, Y: 0, Z: 0.2})
	if !ok {
		t.Fatal("expected trigger")
	}
	if event.SensorID != "sensor0" {
		t.Fatalf("sensor id = %q", event.SensorID)
	}
}

func TestDetectorCooldownSuppressesRepeat(t *testing.T) {
	d := New(0.8, 500*time.Millisecond)
	now := time.Now()
	d.Process("sensor0", Sample{Timestamp: now, X: 0, Y: 0, Z: 1})
	if _, ok := d.Process("sensor0", Sample{Timestamp: now.Add(10 * time.Millisecond), X: 3, Y: 0, Z: 0}); !ok {
		t.Fatal("expected first trigger")
	}
	if _, ok := d.Process("sensor0", Sample{Timestamp: now.Add(100 * time.Millisecond), X: 3, Y: 0, Z: 0}); ok {
		t.Fatal("expected cooldown suppression")
	}
}
