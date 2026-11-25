package main

import (
	"bufio"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"os"
	"path/filepath"
	"strings"

	"github.com/adrg/xdg"
)

func storageDir() string {
	if dataDir != "" {
		return expandHome(dataDir)
	}

	if dir := xdg.UserDirs.Download; dir != "" {
		if fi, err := os.Stat(dir); err == nil && fi.IsDir() {
			return dir
		}
	}

	if home, err := os.UserHomeDir(); err == nil {
		return filepath.Join(home, defaultDirName)
	}
	return "."
}

func expandHome(p string) string {
	if p != "~" && !strings.HasPrefix(p, "~/") && !strings.HasPrefix(p, `~\`) {
		return p
	}
	home, err := os.UserHomeDir()
	if err != nil {
		return p
	}
	rest := strings.TrimLeft(strings.TrimPrefix(p, "~"), `/\`)
	if rest == "" {
		return home
	}
	return filepath.Join(home, rest)
}

func writeFileAtomic(path string, write func(io.Writer) error) (err error) {
	tmp := path + ".tmp"
	f, err := os.Create(tmp)
	if err != nil {
		return err
	}
	defer func() {
		if err != nil {
			_ = os.Remove(tmp)
		}
	}()

	bw := bufio.NewWriter(f)
	if err = write(bw); err != nil {
		_ = f.Close()
		return err
	}
	if err = bw.Flush(); err != nil {
		_ = f.Close()
		return err
	}
	if err = f.Close(); err != nil {
		return err
	}
	return os.Rename(tmp, path)
}

func cleanDataFiles() error {
	dir := storageDir()
	names := []string{
		inputFileName,
		outputFileName,
		inputFileName + ".tmp",
		outputFileName + ".tmp",
	}

	removed := 0
	for _, name := range names {
		p := filepath.Join(dir, name)
		switch err := os.Remove(p); {
		case err == nil:
			ui.say(ui.icons.Clean, "Removed %s", p)
			removed++
		case errors.Is(err, fs.ErrNotExist):
		default:
			return fmt.Errorf("couldn't remove %s: %w", p, err)
		}
	}

	if removed == 0 {
		ui.say(ui.icons.Info, "No proxy lists to remove in %s", dir)
	}
	return nil
}