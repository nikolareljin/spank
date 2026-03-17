package audio

import (
	"embed"
	"errors"
	"fmt"
	"io/fs"
	"math/rand"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
	"time"
)

//go:embed assets/pain/*.mp3 assets/sexy/*.mp3 assets/halo/*.mp3
var embeddedPacks embed.FS

type Player struct {
	CommandTemplate string
	Volume          float64
}

type pack struct {
	name  string
	dir   string
	files []string
}

func init() {
	rand.Seed(time.Now().UnixNano())
}

func AvailableCommand() string {
	candidates := []string{"ffplay", "mpv", "mpg123", "mpg321", "play", "cvlc", "vlc"}
	for _, candidate := range candidates {
		if _, err := exec.LookPath(candidate); err == nil {
			return candidate
		}
	}
	return ""
}

func (p Player) Play(sound string) error {
	filename, data, err := Asset(sound)
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

	path := filepath.Join(tempDir, filename)
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

func Asset(name string) (string, []byte, error) {
	selectedPack, err := resolvePack(name)
	if err != nil {
		return "", nil, err
	}
	file, err := selectedPack.randomFile()
	if err != nil {
		return "", nil, err
	}

	data, err := embeddedPacks.ReadFile(file)
	if err != nil {
		return "", nil, err
	}
	return filepath.Base(file), data, nil
}

func Check() error {
	if AvailableCommand() == "" {
		return errors.New("no supported audio player found in PATH; install ffplay, mpv, mpg123, mpg321, sox/play, or vlc/cvlc")
	}
	return nil
}

func AvailableSounds() []string {
	return []string{"default", "pain", "halo", "sexy"}
}

func defaultTemplate() string {
	switch AvailableCommand() {
	case "ffplay":
		return "ffplay -nodisp -autoexit -loglevel quiet %s"
	case "mpv":
		return "mpv --really-quiet --no-video %s"
	case "mpg123":
		return "mpg123 -q %s"
	case "mpg321":
		return "mpg321 -q %s"
	case "play":
		return "play -q %s"
	case "cvlc":
		return "cvlc --play-and-exit --quiet %s"
	case "vlc":
		return "vlc --intf dummy --play-and-exit --quiet %s"
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

func resolvePack(name string) (*pack, error) {
	switch strings.TrimSpace(strings.ToLower(name)) {
	case "", "default", "pain":
		return newPack("pain", "assets/pain")
	case "halo":
		return newPack("halo", "assets/halo")
	case "sexy":
		return newPack("sexy", "assets/sexy")
	default:
		return nil, fmt.Errorf("unknown sound asset %q; available: %s", name, strings.Join(AvailableSounds(), ", "))
	}
}

func newPack(name, dir string) (*pack, error) {
	entries, err := fs.ReadDir(embeddedPacks, dir)
	if err != nil {
		return nil, err
	}
	files := make([]string, 0, len(entries))
	for _, entry := range entries {
		if entry.IsDir() || !strings.HasSuffix(strings.ToLower(entry.Name()), ".mp3") {
			continue
		}
		files = append(files, filepath.ToSlash(filepath.Join(dir, entry.Name())))
	}
	sort.Strings(files)
	if len(files) == 0 {
		return nil, fmt.Errorf("no audio files found for pack %s", name)
	}
	return &pack{name: name, dir: dir, files: files}, nil
}

func (p *pack) randomFile() (string, error) {
	if len(p.files) == 0 {
		return "", fmt.Errorf("sound pack %s is empty", p.name)
	}
	return p.files[rand.Intn(len(p.files))], nil
}
