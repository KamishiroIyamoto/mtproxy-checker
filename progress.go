package main

import (
	"fmt"
	"time"
)

func renderProgress(st *stats, start time.Time, done <-chan struct{}) {
	if !ui.tty {
		<-done
		return
	}

	frames := ui.spinner()
	ticker := time.NewTicker(100 * time.Millisecond)
	defer ticker.Stop()

	var line statusLine
	for i := 0; ; i++ {
		select {
		case <-done:
			line.clear()
			return
		case <-ticker.C:
			alive := st.tcpAlive.Load()
			line.set(fmt.Sprintf("%c Reachable: %d/%d (%d open) | Handshake: %d/%d | Working: %d | %s",
				frames[i%len(frames)],
				st.tcpDone.Load(), st.total, alive,
				st.mtDone.Load(), alive,
				st.working.Load(),
				time.Since(start).Truncate(time.Second)))
		}
	}
}