package main

import (
	"bufio"
	"encoding/base64"
	"encoding/hex"
	"errors"
	"net"
	"net/url"
	"os"
	"strings"
)

type proxyEntry struct {
	raw    string
	addr   string
	secret []byte
}

func readProxies(path string) (entries []proxyEntry, dupes int, err error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, 0, err
	}
	defer func() {
		if cerr := f.Close(); cerr != nil && err == nil {
			err = cerr
		}
	}()

	seen := make(map[string]struct{})
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

		addr := net.JoinHostPort(strings.ToLower(server), port)
		key := addr + "|" + hex.EncodeToString(secret)
		if _, ok := seen[key]; ok {
			dupes++
			continue
		}
		seen[key] = struct{}{}

		entries = append(entries, proxyEntry{raw: raw, addr: addr, secret: secret})
	}
	return entries, dupes, scanner.Err()
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
		return "", "", nil, errors.New("missing server or port")
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
	return nil, errors.New("invalid secret")
}