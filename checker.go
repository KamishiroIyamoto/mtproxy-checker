package main

import (
	"context"
	"errors"
	"net"
	"sync"
	"sync/atomic"
	"time"

	"github.com/gotd/td/telegram"
	"github.com/gotd/td/telegram/dcs"
	"github.com/gotd/td/transport"
)

type stats struct {
	total    int64
	tcpDone  atomic.Int64
	tcpAlive atomic.Int64
	mtDone   atomic.Int64
	working  atomic.Int64
}

type checkResult struct {
	entry   proxyEntry
	latency time.Duration
}

func check(ctx context.Context, entries []proxyEntry, st *stats) <-chan checkResult {
	tcpJobs := make(chan proxyEntry)
	alive := make(chan proxyEntry, mtprotoWorkers)
	results := make(chan checkResult)

	// Producer.
	go func() {
		defer close(tcpJobs)
		for _, e := range entries {
			select {
			case tcpJobs <- e:
			case <-ctx.Done():
				return
			}
		}
	}()

	var tcpWG sync.WaitGroup
	for range tcpWorkers {
		tcpWG.Go(func() {
			for e := range tcpJobs {
				ok := tcpReachable(ctx, e.addr)
				st.tcpDone.Add(1)
				if !ok {
					continue
				}
				st.tcpAlive.Add(1)
				select {
				case alive <- e:
				case <-ctx.Done():
					return
				}
			}
		})
	}
	go func() {
		tcpWG.Wait()
		close(alive)
	}()

	var mtWG sync.WaitGroup
	for range mtprotoWorkers {
		mtWG.Go(func() {
			for e := range alive {
				latency, ok := checkMTProto(ctx, e)
				st.mtDone.Add(1)
				if ok {
					st.working.Add(1)
					results <- checkResult{entry: e, latency: latency}
				}
			}
		})
	}
	go func() {
		mtWG.Wait()
		close(results)
	}()

	return results
}

func tcpReachable(ctx context.Context, addr string) bool {
	d := net.Dialer{Timeout: tcpTimeout}
	conn, err := d.DialContext(ctx, "tcp", addr)
	if err != nil {
		return false
	}
	_ = conn.Close()
	return true
}

func checkMTProto(parent context.Context, e proxyEntry) (time.Duration, bool) {
	ctx, cancel := context.WithTimeout(parent, mtprotoTimeout)
	defer cancel()

	base, err := dcs.MTProxy(e.addr, e.secret, dcs.MTProxyOptions{})
	if err != nil {
		return 0, false
	}

	client := telegram.NewClient(telegram.TestAppID, telegram.TestAppHash, telegram.Options{
		Resolver:  &failFastResolver{Resolver: base, cancel: cancel, limit: mtprotoAttempts},
		NoUpdates: true,
	})

	type outcome struct {
		err     error
		latency time.Duration
	}
	done := make(chan outcome, 1)

	go func() {
		start := time.Now()
		err := client.Run(ctx, func(ctx context.Context) error {
			_, err := client.API().HelpGetNearestDC(ctx)
			return err
		})
		done <- outcome{err: err, latency: time.Since(start)}
	}()

	select {
	case o := <-done:
		return o.latency, o.err == nil
	case <-ctx.Done():
		return 0, false
	}
}

var errTooManyAttempts = errors.New("proxy failed, reconnect suppressed")

type failFastResolver struct {
	dcs.Resolver
	cancel   context.CancelFunc
	limit    int32
	attempts atomic.Int32
}

func (r *failFastResolver) Primary(ctx context.Context, dc int, list dcs.List) (transport.Conn, error) {
	if r.attempts.Add(1) > r.limit {
		r.cancel()
		return nil, errTooManyAttempts
	}
	return r.Resolver.Primary(ctx, dc, list)
}