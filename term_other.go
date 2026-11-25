package main

import (
	"os"
	"runtime"
	"strings"
)

func enableANSI(*os.File) bool { return true }

func unicodeSupported() bool {
	if os.Getenv("TERM") == "linux" {
		return false
	}

	loc := ""
	for _, k := range []string{"LC_ALL", "LC_CTYPE", "LANG"} {
		if v := os.Getenv(k); v != "" {
			loc = v
			break
		}
	}
	if loc == "" {
		return runtime.GOOS == "darwin"
	}

	loc = strings.ToLower(loc)
	return strings.Contains(loc, "utf-8") || strings.Contains(loc, "utf8")
}