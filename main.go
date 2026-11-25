package main

import (
	"cmp"
	"context"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"os/signal"
	"path/filepath"
	"slices"
	"sync"
	"syscall"
	"time"
)

func main() {
	flag.Usage = usage
	cleanOnly := flag.Bool("clean", false, "")
	flag.Parse()

	if flag.NArg() > 0 {
		ui.fail(fmt.Errorf("unexpected argument %q", flag.Arg(0)))
		flag.Usage()
		os.Exit(2)
	}

	var err error
	if *cleanOnly {
		err = cleanDataFiles()
	} else {
		err = run()
	}

	switch {
	case err == nil:
	case errors.Is(err, context.Canceled):
		ui.say(ui.icons.Stop, "Cancelled - nothing was checked.")
		os.Exit(130)
	default:
		ui.fail(err)
		os.Exit(1)
	}
}

func usage() {
	w := flag.CommandLine.Output()
	fmt.Fprintf(w, `Usage: mtproxy [--clean]

Downloads a fresh MTProto proxy list, checks every proxy and prints
the working ones, fastest first.

Options:
  --clean     delete %s and %s, then exit
  -h, --help  show this help

Files are kept in: %s

Environment:
  MTPROXY_EMOJI=0|1   force plain-text or emoji output
`, inputFileName, outputFileName, storageDir())
}

func run() error {
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	// После первого Ctrl+C возвращаем стандартное поведение: второй завершает сразу.
	go func() { <-ctx.Done(); stop() }()

	dir := storageDir()
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return fmt.Errorf("can't create folder %s: %w", dir, err)
	}
	inputFile := filepath.Join(dir, inputFileName)
	outputFile := filepath.Join(dir, outputFileName)

	ui.say(ui.icons.Download, "Downloading a fresh proxy list...")
	if err := downloadProxyList(ctx, inputFile); err != nil {
		if ctx.Err() != nil {
			return ctx.Err()
		}
		fi, statErr := os.Stat(inputFile)
		if statErr != nil {
			return fmt.Errorf("couldn't download the proxy list (%v) - check your internet connection and try again", err)
		}
		ui.say(ui.icons.Warn, "Couldn't download a fresh list: %v", err)
		ui.say(ui.icons.Info, "Falling back to the copy saved %s ago", humanAge(time.Since(fi.ModTime())))
	}

	entries, dupes, err := readProxies(inputFile)
	if err != nil {
		return fmt.Errorf("couldn't read %s: %w", inputFile, err)
	}
	if len(entries) == 0 {
		return fmt.Errorf("no usable proxies in %s - the list looks empty or malformed", inputFile)
	}

	msg := fmt.Sprintf("Got %s to check", count(len(entries), "proxy", "proxies"))
	if dupes > 0 {
		msg += fmt.Sprintf(" (skipped %s)", count(dupes, "duplicate", "duplicates"))
	}
	ui.say(ui.icons.List, "%s", msg)
	ui.say(ui.icons.Check, "Checking them now - this usually takes under a minute. Press Ctrl+C to stop early.")

	st := &stats{total: int64(len(entries))}
	start := time.Now()

	done := make(chan struct{})
	var progressWG sync.WaitGroup
	progressWG.Go(func() { renderProgress(st, start, done) })

	var working []checkResult
	for r := range check(ctx, entries, st) {
		working = append(working, r)
	}

	close(done)
	progressWG.Wait()

	elapsed := time.Since(start).Round(100 * time.Millisecond)
	interrupted := ctx.Err() != nil

	slices.SortFunc(working, func(a, b checkResult) int {
		return cmp.Compare(a.latency, b.latency)
	})

	if len(working) == 0 {
		if interrupted {
			ui.say(ui.icons.Stop, "Stopped after %s - no working proxies found yet. Previous results were left untouched.", elapsed)
			return nil
		}
		if err := saveResults(outputFile, nil); err != nil {
			return err
		}
		ui.say(ui.icons.Empty, "No working proxies this time (%s checked in %s).",
			count(len(entries), "proxy", "proxies"), elapsed)
		ui.say(ui.icons.Info, "Public lists change often - try again in a while.")
		return nil
	}

	if err := saveResults(outputFile, working); err != nil {
		return err
	}

	found := count(len(working), "working proxy", "working proxies")
	if interrupted {
		ui.say(ui.icons.Stop, "Stopped early after %s - kept the %s found so far.", elapsed, found)
	} else {
		ui.say(ui.icons.Party, "Done in %s: %s out of %d!", elapsed, found, len(entries))
	}
	ui.say(ui.icons.Fast, "Fastest one answered in %s", working[0].latency.Round(time.Millisecond))
	ui.say(ui.icons.Save, "Saved to %s", outputFile)

	fmt.Fprintln(os.Stderr)
	ui.say(ui.icons.OK, "Working proxies, fastest first:")
	for _, r := range working {
		fmt.Println(r.entry.raw)
	}
	return nil
}

func saveResults(path string, working []checkResult) error {
	err := writeFileAtomic(path, func(w io.Writer) error {
		for _, r := range working {
			if _, err := fmt.Fprintln(w, r.entry.raw); err != nil {
				return err
			}
		}
		return nil
	})
	if err != nil {
		return fmt.Errorf("couldn't save results to %s: %w", path, err)
	}
	return nil
}

func count(n int, one, many string) string {
	if n == 1 {
		return "1 " + one
	}
	return fmt.Sprintf("%d %s", n, many)
}

func humanAge(d time.Duration) string {
	switch {
	case d < time.Minute:
		return "less than a minute"
	case d < time.Hour:
		return count(int(d/time.Minute), "minute", "minutes")
	case d < 48*time.Hour:
		return count(int(d/time.Hour), "hour", "hours")
	default:
		return count(int(d/(24*time.Hour)), "day", "days")
	}
}