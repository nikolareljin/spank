package audio

import "testing"

func TestAvailableSoundsResolveToAssets(t *testing.T) {
	for _, sound := range AvailableSounds() {
		name, data, err := Asset(sound)
		if err != nil {
			t.Fatalf("asset(%q): %v", sound, err)
		}
		if name == "" {
			t.Fatalf("asset(%q) returned empty filename", sound)
		}
		if len(data) == 0 {
			t.Fatalf("asset(%q) returned empty data", sound)
		}
	}
}
