package main

import "time"

const (
	proxyListURL = "https://raw.githubusercontent.com/SoliSpirit/mtproto/master/all_proxies.txt"
	inputFileName = "all_proxies.txt"
	outputFileName = "working_proxies.txt"
	dataDir = ""
	defaultDirName = "Downloads"
	downloadTimeout = 60 * time.Second
	tcpWorkers = 128
	tcpTimeout = 3 * time.Second
	mtprotoWorkers = 64
	mtprotoTimeout = 10 * time.Second
	mtprotoAttempts = 1
)