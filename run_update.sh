#!/bin/bash
set -e

MODE=$1

if [[ "$MODE" != "dev" && "$MODE" != "qa" && "$MODE" != "prd" ]]; then
  echo "Usage: $0 [dev|qa|prd]"
  exit 1
fi 

 
echo "▶ Running docker-compose override with $MODE.env ..."
# MODE=$MODE sudo python ./docker/update_compose.py 
MODE=$MODE python ./docker/update_compose.py 
#MODE=$MODE python3 ./docker/docker-mapping-env.py  data/docker-compose.yml
 
 