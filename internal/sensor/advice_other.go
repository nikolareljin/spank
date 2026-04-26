//go:build !linux

package sensor

func DiscoveryAdvice(string) []string {
	return nil
}
