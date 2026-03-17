//go:build !linux

package sensor

import (
	"context"
	"errors"
	"time"
)

type IIOProvider struct {
	SysfsRoot string
	DmiRoot   string
}

func NewIIOProvider(sysfsRoot, dmiRoot string) *IIOProvider {
	return &IIOProvider{SysfsRoot: sysfsRoot, DmiRoot: dmiRoot}
}

func (p *IIOProvider) Discover(context.Context) ([]SensorInfo, error) {
	return nil, errors.New("spank currently supports Linux IIO accelerometers only")
}

func (p *IIOProvider) Open(context.Context, SensorInfo, time.Duration) (Stream, error) {
	return nil, errors.New("spank currently supports Linux IIO accelerometers only")
}

func FindSensor(context.Context, Provider, string) (SensorInfo, error) {
	return SensorInfo{}, errors.New("spank currently supports Linux IIO accelerometers only")
}
