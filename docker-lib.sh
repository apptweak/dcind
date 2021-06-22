#!/bin/bash
# Based on https://github.com/concourse/docker-image-resource/blob/master/assets/common.sh

LOG_FILE=${LOG_FILE:-/tmp/docker.log}
SKIP_PRIVILEGED=${SKIP_PRIVILEGED:-false}
DOCKER_DATA_ROOT=${DOCKER_DATA_ROOT:-/scratch/docker}
STARTUP_TIMEOUT=${STARTUP_TIMEOUT:-300}

sanitize_cgroups() {
  mkdir -p /sys/fs/cgroup
  mountpoint -q /sys/fs/cgroup || \
    mount -t tmpfs -o uid=0,gid=0,mode=0755 cgroup /sys/fs/cgroup

  mount -o remount,rw /sys/fs/cgroup

  sed -e 1d /proc/cgroups | while read sys hierarchy num enabled; do
    if [ "$enabled" != "1" ]; then
      # subsystem disabled; skip
      continue
    fi

    grouping="$(cat /proc/self/cgroup | cut -d: -f2 | grep "\\<$sys\\>")" || true
    if [ -z "$grouping" ]; then
      # subsystem not mounted anywhere; mount it on its own
      grouping="$sys"
    fi

    mountpoint="/sys/fs/cgroup/$grouping"

    mkdir -p "$mountpoint"

    # clear out existing mount to make sure new one is read-write
    if mountpoint -q "$mountpoint"; then
      umount "$mountpoint"
    fi

    mount -n -t cgroup -o "$grouping" cgroup "$mountpoint"

    if [ "$grouping" != "$sys" ]; then
      if [ -L "/sys/fs/cgroup/$sys" ]; then
        rm "/sys/fs/cgroup/$sys"
      fi

      ln -s "$mountpoint" "/sys/fs/cgroup/$sys"
    fi
  done

  if ! test -e /sys/fs/cgroup/systemd ; then
    mkdir /sys/fs/cgroup/systemd
    mount -t cgroup -o none,name=systemd none /sys/fs/cgroup/systemd
  fi
}

start_docker() {
  message header "Setting up docker";message info "Starting Docker..."

  if [ -f /tmp/docker.pid ]; then
    message info "Docker is already running"
    return
  fi

  mkdir -p /var/log
  mkdir -p /var/run

  if [ "$SKIP_PRIVILEGED" = "false" ]; then
    sanitize_cgroups

    # check for /proc/sys being mounted readonly, as systemd does
    if grep '/proc/sys\s\+\w\+\s\+ro,' /proc/mounts >/dev/null; then
      mount -o remount,rw /proc/sys
    fi
  fi

  local mtu=$(cat /sys/class/net/$(ip route get 8.8.8.8|awk '{ print $5 }')/mtu)
  local server_args="--mtu ${mtu}"
  local registry=""

  for registry in $1; do
    server_args="${server_args} --insecure-registry ${registry}"
  done

  if [ -n "$2" ]; then
    server_args="${server_args} --registry-mirror $2"
  fi

  export server_args LOG_FILE
  trap stop_docker EXIT

  try_start() {
    dockerd --data-root /scratch/docker ${server_args} >$LOG_FILE 2>&1 &
    echo $! > /tmp/docker.pid

    sleep 1

    message info "Waiting for docker to come up ..."
    until docker info >/dev/null 2>&1; do
      sleep 1
      if ! kill -0 "$(cat /tmp/docker.pid)" 2>/dev/null; then
        return 1
      fi
    done
  }

  if [ "$(command -v declare)" ]; then
    declare -fx try_start

    if ! timeout ${STARTUP_TIMEOUT} bash -ce 'while true; do try_start && break; done'; then
      cat "${LOG_FILE}"
      echo Docker failed to start within ${STARTUP_TIMEOUT} seconds.
      return 1
    fi
  else
    try_start
  fi

  message info "Starting Docker: OK"
}

stop_docker() {
  echo "Stopping Docker..."

  if [ ! -f /tmp/docker.pid ]; then
    return 0
  fi

  local pid=$(cat /tmp/docker.pid)
  if [ -z "$pid" ]; then
    return 0
  fi

  kill -TERM $pid
  rm /tmp/docker.pid
}


# Helper functions for the differnt tasks
# ---------------------------------------

# The image_names array needs to be defined beforehand
# Example:
# load_images db-image api-image
load_images() {
  # The docker images need to be preloaded to enable caching
  # and to let concourse access the private registry
  message info "Load the docker images from the inputs"

  local image_names=("$@") # get all argumets to load_images into an array

  # Load each image from the corresponding folder and tag it correctly
  # The structure of the folder is explained here: https://github.com/concourse/registry-image-resource#in-fetch-the-images-rootfs-and-metadata
  # Note that this script works with the new registry-image resource, not docker-image
  for image_name in "${image_names[@]}"; do
      docker load --quiet --input "${image_name}/image.tar" &
  done

  wait

  message info "This is just to visually check in the log that images have been loaded successfully"
  docker images
}



# Use the wait-for-it script to wait for services to come up
# See: https://github.com/vishnubob/wait-for-it
# Usage: wait_for_startup localhost:5432 localhost:80
wait_for_startup() {
  message info "Wait for services to start"

  local services=("$@")

  for service in "${services[@]}"; do
      wait-for-it "${service}" --timeout=180 --strict
  done
}
