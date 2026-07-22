#!/usr/bin/env bash
# Rack topology script. The NameNode calls it with each DataNode's IP address as an argument
# and expects one rack path per line, in order. Static IPs from docker-compose.yml put
# dn1/dn2 in rack1 (172.28.1.x) and dn3/dn4 in rack2 (172.28.2.x).
for arg in "$@"; do
  case "$arg" in
    172.28.1.*) echo /rack1 ;;
    172.28.2.*) echo /rack2 ;;
    *)          echo /default-rack ;;
  esac
done
