package main

import (
	"context"
	"errors"
	"fmt"
	"io"
	"net/http"
)

func downloadProxyList(ctx context.Context, dst string) error {
	ctx, cancel := context.WithTimeout(ctx, downloadTimeout)
	defer cancel()

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, proxyListURL, nil)
	if err != nil {
		return err
	}

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return err
	}
	defer func() { _ = resp.Body.Close() }()

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("server responded with %s", resp.Status)
	}

	return writeFileAtomic(dst, func(w io.Writer) error {
		n, err := io.Copy(w, resp.Body)
		if err != nil {
			return err
		}
		if n == 0 {
			return errors.New("the downloaded list is empty")
		}
		return nil
	})
}