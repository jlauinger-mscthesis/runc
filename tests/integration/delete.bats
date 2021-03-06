#!/usr/bin/env bats

load helpers

function setup() {
  teardown_busybox
  setup_busybox
}

function teardown() {
  teardown_busybox
}

@test "runc delete" {
  # run busybox detached
  runc run -d --console-socket $CONSOLE_SOCKET test_busybox
  [ "$status" -eq 0 ]

  # check state
  testcontainer test_busybox running

  runc kill test_busybox KILL
  [ "$status" -eq 0 ]
  # wait for busybox to be in the destroyed state
  retry 10 1 eval "__runc state test_busybox | grep -q 'stopped'"

  # delete test_busybox
  runc delete test_busybox
  [ "$status" -eq 0 ]

  runc state test_busybox
  [ "$status" -ne 0 ]
}

@test "runc delete --force" {
  # run busybox detached
  runc run -d --console-socket $CONSOLE_SOCKET test_busybox
  [ "$status" -eq 0 ]

  # check state
  testcontainer test_busybox running

  # force delete test_busybox
  runc delete --force test_busybox

  runc state test_busybox
  [ "$status" -ne 0 ]
}

@test "runc delete --force ignore not exist" {
  runc delete --force notexists
  [ "$status" -eq 0 ]
}

@test "runc delete --force in cgroupv2 with subcgroups" {
  requires cgroups_v2 root
  set_cgroups_path "$BUSYBOX_BUNDLE"

  # grant `rw` priviledge to `/sys/fs/cgroup`
  cat "${BUSYBOX_BUNDLE}/config.json"\
   | jq '.mounts |= map((select(.type=="cgroup") | .options -= ["ro"]) // .)'\
   > "${BUSYBOX_BUNDLE}/config.json.tmp"
  mv "${BUSYBOX_BUNDLE}/config.json"{.tmp,}

  # run busybox detached
  runc run -d --console-socket $CONSOLE_SOCKET test_busybox
  [ "$status" -eq 0 ]

  # check state
  testcontainer test_busybox running

  # create a sub process
  __runc exec -d test_busybox sleep 1d
  [ "$status" -eq 0 ]

  # find the pid of sleep
  pid=$(__runc exec test_busybox ps -a | grep 1d | awk '{print $1}')
  [[ ${pid} =~ [0-9]+ ]]

  # create subcgroups
  cat <<EOF > nest.sh
  cd /sys/fs/cgroup
  for f in \$(cat cgroup.controllers); do echo +\$f > cgroup.subtree_control; done
  mkdir foo
  cd foo
  echo threaded > cgroup.type
  echo ${pid} > cgroup.threads
  cat cgroup.threads
EOF
  cat nest.sh | runc exec test_busybox sh
  [[ ${output} =~ [0-9]+ ]]

  # check create subcgroups success
  [ -d $CGROUP_PATH/foo ]

  # check cgroup.threads' value
  runc exec test_busybox cat /sys/fs/cgroup/foo/cgroup.threads
  [[ ${output} =~ [0-9]+ ]]

  # force delete test_busybox
  runc delete --force test_busybox

  runc state test_busybox
  [ "$status" -ne 0 ]

  # check delete subcgroups success
  [ ! -d $CGROUP_PATH/foo ]
}
