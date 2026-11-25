package main

import (
	"fmt"
	"os"
	"strings"
	"unicode"
	"unicode/utf8"

	"golang.org/x/term"
)

type iconSet struct {
	Download, List, Check, OK, Warn, Error, Save, Stop, Party, Empty, Fast, Clean, Info string
}

var emojiIcons = iconSet{
	Download: "📥", List: "📋", Check: "🔎", OK: "✅", Warn: "⚠️", Error: "❌",
	Save: "💾", Stop: "🛑", Party: "🎉", Empty: "😕", Fast: "⚡", Clean: "🧹", Info: "💡",
}

var plainIcons = iconSet{
	Download: "*", List: "*", Check: "*", OK: "[OK]", Warn: "[!]", Error: "[ERR]",
	Save: "*", Stop: "[!]", Party: "[OK]", Empty: "[!]", Fast: "*", Clean: "-", Info: "*",
}

type console struct {
	icons   iconSet
	tty     bool
	ansi    bool
	unicode bool
}

var ui = newConsole()

func newConsole() *console {
	c := &console{tty: term.IsTerminal(int(os.Stderr.Fd()))}
	dumb := os.Getenv("TERM") == "dumb"

	c.unicode = !dumb && unicodeSupported()
	switch strings.ToLower(os.Getenv("MTPROXY_EMOJI")) {
	case "0", "false", "no", "off":
		c.unicode = false
	case "1", "true", "yes", "on":
		c.unicode = true
	}

	c.ansi = c.tty && !dumb && enableANSI(os.Stderr)

	c.icons = plainIcons
	if c.unicode {
		c.icons = emojiIcons
	}
	return c
}

func (c *console) say(icon, format string, args ...any) {
	fmt.Fprintf(os.Stderr, "%s %s\n", icon, fmt.Sprintf(format, args...))
}

func (c *console) fail(err error) {
	msg := err.Error()
	if msg == "" {
		msg = "unknown error"
	}
	r, n := utf8.DecodeRuneInString(msg)
	c.say(c.icons.Error, "%s", string(unicode.ToUpper(r))+msg[n:])
}

func (c *console) spinner() []rune {
	if c.unicode {
		return []rune("⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏")
	}
	return []rune(`|/-\`)
}

func (c *console) width() int {
	w, _, err := term.GetSize(int(os.Stderr.Fd()))
	if err != nil {
		return 0
	}
	return w
}

type statusLine struct{ shown int }

func (s *statusLine) set(text string) {
	if w := ui.width(); w > 1 {
		text = truncateRunes(text, w-1)
	}
	n := utf8.RuneCountInString(text)
	if ui.ansi {
		fmt.Fprint(os.Stderr, "\r\033[K"+text)
	} else {
		fmt.Fprint(os.Stderr, "\r"+text+strings.Repeat(" ", max(0, s.shown-n)))
	}
	s.shown = n
}

func (s *statusLine) clear() {
	if s.shown == 0 {
		return
	}
	if ui.ansi {
		fmt.Fprint(os.Stderr, "\r\033[K")
	} else {
		fmt.Fprint(os.Stderr, "\r"+strings.Repeat(" ", s.shown)+"\r")
	}
	s.shown = 0
}

func truncateRunes(s string, n int) string {
	if utf8.RuneCountInString(s) <= n {
		return s
	}
	return string([]rune(s)[:n])
}