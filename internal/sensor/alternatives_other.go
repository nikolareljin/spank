//go:build !linux

package sensor

func ExplainDiscoveryFailure(err error) error {
	return err
}
