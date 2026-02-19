#!/bin/bash

set -eu

# The following variables are available for use:
# - ROLE contains the role of this execution context, client or server
# - SERVER_PARAMS contains user-supplied command line parameters
# - CLIENT_PARAMS contains user-supplied command line parameters

case $TESTCASE in
versionnegotiation|handshake|transfer|retry|resumption|http3|multiconnect|zerortt|chacha20|keyupdate|v2)
	:
;;
*)
	exit 127
;;
esac

# set up the routing needed for the simulation
/setup.sh

LOG=/logs/log.txt

if [ "$ROLE" == "client" ]; then
	exit 127
elif [ "$ROLE" == "server" ]; then
	echo "starting lighttpd server"
	lighttpd -f /lighttpd.cfg

	cp /certs/cert.pem /tmp/
	cp /certs/priv.key /tmp/cert.pem.key

	export LD_LIBRARY_PATH=/usr/local/lib
	echo "haproxy version $(haproxy -v)"
	echo "starting haproxy..."

	case $TESTCASE in
		retry)
			HAP_EXTRA_ARGS="quic-force-retry" /usr/local/sbin/haproxy -d -dM -f /quic.cfg &> $LOG &
		;;
		*)
			HAP_EXTRA_ARGS="" /usr/local/sbin/haproxy -d -dM -f /quic.cfg &> $LOG &
		;;
	esac
	HAP_PID=$!

	query_prometheus() {
		echo "# testcase: $TESTCASE" >> /logs/prometheus.txt
		curl -s http://localhost:8405/metrics >> /logs/prometheus.txt 2>&1 || true
	}

	cleanup() {
		query_prometheus
		kill -TERM $HAP_PID 2>/dev/null || true
		wait $HAP_PID 2>/dev/null || true
		exit 0
	}
	trap cleanup SIGUSR1 TERM INT

	wait $HAP_PID || true
	query_prometheus
fi
