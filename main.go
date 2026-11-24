package main

import (
	"bufio"
	"context"
	"encoding/base64"
	"encoding/hex"
	"fmt"
	"net"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"github.com/adrg/xdg"
	"github.com/gotd/td/telegram"
	"github.com/gotd/td/telegram/dcs"
	"golang.org/x/term"
)

const (
	workers = 30
	timeout = 10 * time.Second
)

func downloadsDir() string {
	if dir := xdg.UserDirs.Download; dir != "" {
		if fi, err := os.Stat(dir); err == nil && fi.IsDir() {
			return dir
		}
	}

	if home, err := os.UserHomeDir(); err == nil {
		return filepath.Join(home, "Downloads")
	}
	return "."
}

type proxyEntry struct {
	raw    string
	addr   string
	secret []byte
}

type result struct {
	entry proxyEntry
	ok    bool
}

func main() {
	dir := downloadsDir()
	inputFile := filepath.Join(dir, "all_proxies.txt")
	outputFile := filepath.Join(dir, "available_proxies.txt")

	if err := os.MkdirAll(dir, 0o755); err != nil {
		fmt.Fprintf(os.Stderr, "Error creating %s: %v\n", dir, err)
		os.Exit(1)
	}

	entries, err := readProxies(inputFile)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error reading %s: %v\n", inputFile, err)
		os.Exit(1)
	}
	if len(entries) == 0 {
		fmt.Fprintf(os.Stderr, "No proxies to check in %s\n", inputFile)
		os.Exit(1)
	}

	out, err := os.OpenFile(outputFile, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0o644)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error opening %s: %v\n", outputFile, err)
		os.Exit(1)
	}

	defer func() {
		if cerr := out.Close(); cerr != nil {
			fmt.Fprintf(os.Stderr, "Error closing %s: %v\n", outputFile, cerr)
		}
	}()

	total := len(entries)
	var processed, working int64
	done := make(chan struct{})

	var progressWG sync.WaitGroup
	progressWG.Add(1)
	go func() {
		defer progressWG.Done()
		renderProgress(total, &processed, &working, done)
	}()

	jobs := make(chan proxyEntry)
	results := make(chan result)

	var wg sync.WaitGroup
	for i := 0; i < workers; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for e := range jobs {
				results <- result{entry: e, ok: checkProxy(e)}
			}
		}()
	}

	go func() {
		for _, e := range entries {
			jobs <- e
		}
		close(jobs)
	}()

	go func() {
		wg.Wait()
		close(results)
	}()

	writer := bufio.NewWriter(out)

	var availableList []string
	for r := range results {
		atomic.AddInt64(&processed, 1)
		if r.ok {
			atomic.AddInt64(&working, 1)
			availableList = append(availableList, r.entry.raw)

			if _, werr := writer.WriteString(r.entry.raw + "\n"); werr != nil {
				fmt.Fprintf(os.Stderr, "Error writing output: %v\n", werr)
			}
		}
	}

	if err := writer.Flush(); err != nil {
		fmt.Fprintf(os.Stderr, "Error flushing output: %v\n", err)
	}

	close(done)
	progressWG.Wait()

	fmt.Println("Working proxies:")
	for _, p := range availableList {
		fmt.Println(p)
	}
}

func renderProgress(total int, processed, working *int64, done <-chan struct{}) {
	if !term.IsTerminal(int(os.Stderr.Fd())) {
		<-done
		return
	}

	frames := []rune("⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏")
	ticker := time.NewTicker(100 * time.Millisecond)
	defer ticker.Stop()

	i := 0
	for {
		select {
		case <-done:
			fmt.Fprint(os.Stderr, "\r\033[K")
			return
		case <-ticker.C:
			p := atomic.LoadInt64(processed)
			w := atomic.LoadInt64(working)
			remaining := int64(total) - p
			fmt.Fprintf(os.Stderr, "\r\033[K%c Checked: %d/%d | Working: %d | Remaining: %d",
				frames[i%len(frames)], p, total, w, remaining)
			i++
		}
	}
}

func readProxies(path string) (entries []proxyEntry, err error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer func() {
		if cerr := f.Close(); cerr != nil && err == nil {
			err = cerr
		}
	}()

	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		raw := strings.TrimSpace(scanner.Text())
		if raw == "" || strings.HasPrefix(raw, "#") {
			continue
		}
		server, port, secret, perr := parseProxyURL(raw)
		if perr != nil {
			continue
		}
		entries = append(entries, proxyEntry{
			raw:    raw,
			addr:   net.JoinHostPort(server, port),
			secret: secret,
		})
	}
	return entries, scanner.Err()
}

func parseProxyURL(raw string) (server, port string, secret []byte, err error) {
	u, err := url.Parse(raw)
	if err != nil {
		return "", "", nil, err
	}
	q := u.Query()
	server = q.Get("server")
	port = q.Get("port")
	if server == "" || port == "" {
		return "", "", nil, fmt.Errorf("missing server or port")
	}
	secret, err = decodeSecret(q.Get("secret"))
	if err != nil {
		return "", "", nil, err
	}
	return server, port, secret, nil
}

func decodeSecret(s string) ([]byte, error) {
	if b, err := hex.DecodeString(s); err == nil {
		return b, nil
	}
	if b, err := base64.RawURLEncoding.DecodeString(s); err == nil {
		return b, nil
	}
	if b, err := base64.URLEncoding.DecodeString(s); err == nil {
		return b, nil
	}
	return nil, fmt.Errorf("invalid secret")
}

func checkProxy(e proxyEntry) bool {
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()

	done := make(chan bool, 1)
	go func() {
		done <- runCheck(ctx, e)
	}()

	select {
	case ok := <-done:
		return ok
	case <-ctx.Done():
		return false
	}
}

func runCheck(ctx context.Context, e proxyEntry) bool {
	resolver, err := dcs.MTProxy(e.addr, e.secret, dcs.MTProxyOptions{})
	if err != nil {
		return false
	}

	client := telegram.NewClient(telegram.TestAppID, telegram.TestAppHash, telegram.Options{
		Resolver: resolver,
	})

	err = client.Run(ctx, func(ctx context.Context) error {
		_, err := client.API().HelpGetNearestDC(ctx)
		return err
	})
	return err == nil
}