#!/bin/bash -u

cd "$(dirname $0)"
shdir="$(pwd)"

hosts="host1 host2 host3"

pids=""
for host in ${hosts}; do
  ssh ${host} "bash ${shdir}/sar2png.sh $*" &
  pids="${pids} $!"
done

wait
exit 0
