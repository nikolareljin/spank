package audio

import (
	"encoding/base64"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

const defaultWAVBase64 = "UklGRjwAAABXQVZFZm10IBAAAAABAAEARKwAAIhYAQACABAAZGF0YRgAAAAAAP//AAD//wAA//8AAP//AAD//wAA"

type Player struct {
	CommandTemplate string
	Volume          float64
}

func AvailableCommand() string {
	candidates := []string{"paplay", "aplay", "ffplay", "play"}
	for _, candidate := range candidates {
		if _, err := exec.LookPath(candidate); err == nil {
			return candidate
		}
	}
	return ""
}

func (p Player) Play(sound string) error {
	data, err := Asset(sound)
	if err != nil {
		return err
	}

	commandTemplate := strings.TrimSpace(p.CommandTemplate)
	if commandTemplate == "" {
		commandTemplate = defaultTemplate()
	}
	if commandTemplate == "" {
		fmt.Print("\a")
		return nil
	}

	tempDir, err := os.MkdirTemp("", "spank-audio-*")
	if err != nil {
		return err
	}
	defer os.RemoveAll(tempDir)

	path := filepath.Join(tempDir, "sound.wav")
	if err := os.WriteFile(path, data, 0o600); err != nil {
		return err
	}

	command, args, err := buildCommand(commandTemplate, path)
	if err != nil {
		return err
	}
	cmd := exec.Command(command, args...)
	output, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("play sound: %w: %s", err, strings.TrimSpace(string(output)))
	}
	return nil
}

func Asset(name string) ([]byte, error) {
	switch strings.TrimSpace(name) {
	case "", "default":
		return base64.StdEncoding.DecodeString(defaultWAVBase64)
	default:
		return nil, fmt.Errorf("unknown sound asset %q", name)
	}
}

func Check() error {
	if AvailableCommand() == "" {
		return errors.New("no supported audio player found in PATH; install paplay, aplay, ffplay, or sox/play")
	}
	return nil
}

func defaultTemplate() string {
	switch AvailableCommand() {
	case "paplay":
		return "paplay %s"
	case "aplay":
		return "aplay -q %s"
	case "ffplay":
		return "ffplay -nodisp -autoexit -loglevel quiet %s"
	case "play":
		return "play -q %s"
	default:
		return ""
	}
}

func buildCommand(template, path string) (string, []string, error) {
	parts := strings.Fields(template)
	if len(parts) == 0 {
		return "", nil, errors.New("empty player command")
	}
	for i := range parts {
		if strings.Contains(parts[i], "%s") {
			parts[i] = strings.ReplaceAll(parts[i], "%s", path)
		}
	}
	if !strings.Contains(template, "%s") {
		parts = append(parts, path)
	}
	return parts[0], parts[1:], nil
}
