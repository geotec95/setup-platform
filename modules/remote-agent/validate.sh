#!/bin/bash
set -Eeuo pipefail
docker ps --format '{{.Names}}' | grep -q '^remote-agent_prometheus-agent' && echo "remote-agent: OK" || { echo "remote-agent: FAIL"; exit 1; }
