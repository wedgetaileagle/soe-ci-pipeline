#!/bin/bash

# Instruct Satellite to rebuild the test VMs
#
# e.g ${WORKSPACE}/scripts/buildtestvms.sh 'test'
#
# this will tell Foreman to rebuild all machines in hostgroup TESTVM_HOSTGROUP

# Load common parameter variables
. $(dirname "${0}")/common.sh

if [[ -z ${PUSH_USER} ]] || [[ -z ${SATELLITE} ]]  || [[ -z ${RSA_ID} ]] \
   || [[ -z ${ORG} ]] || [[ -z ${TESTVM_HOSTCOLLECTION} ]]; then
  err "Environment variable PUSH_USER, SATELLITE, RSA_ID, ORG " \
        "or TESTVM_HOSTCOLLECTION not set or not found."
  exit ${WORKSPACE_ERR}
fi

# get our test machines into an array variable TEST_VM_LIST
#function get_test_vm_list() {
#  local J=0
#  for I in $(ssh -q -l ${PUSH_USER} -i ${RSA_ID} ${SATELLITE} \
#      "hammer content-host list --organization \"${ORG}\" \
#          --host-collection \"$TESTVM_HOSTCOLLECTION\" \
#          | tail -n +4 | cut -f2 -d \"|\" | head -n -1"); do
#    TEST_VM_LIST[$J]=$I
#    ((J+=1))
#  done
#}
#get_test_vm_list # populate TEST_VM_LIST

function get_dev_vm_list() {
  local J=0
  hostlist=$(grep -A20 'def devHosts' ${WORKSPACE}/jenkins-config/soe_2_dev.groovy \
    | grep -B20 "]" | grep : | awk -F: '{ print $2 }' | tr -d "\',")
  TEST_VM_LIST=( $hostlist )
}

get_dev_vm_list

# Error out if no test VM's are available.
if [ $(echo ${#TEST_VM_LIST[@]}) -eq 0 ]; then
  err "No test VMs configured"
  exit ${WORKSPACE_ERR}
fi

# rebuild test VMs
for I in "${TEST_VM_LIST[@]}"; do
  info "Rebuilding VM ID $I"
  ssh -q -l ${PUSH_USER} -i ${RSA_ID} ${SATELLITE} \
        "hammer host update --id $I --build yes"

  _PROBED_STATUS=$(ssh -q -l ${PUSH_USER} -i ${RSA_ID} ${SATELLITE} "hammer host status --id $I" | grep Power | cut -f2 -d: | tr -d ' ')

  # different hypervisors report power status with different words. parse and get a single word per status
  # - KVM uses running / shutoff
  # - VMware uses poweredOn / poweredOff
  # - libvirt uses up / down
  # add others as you come across them and please submit to https://github.com/ggatward/soe-ci-pipeline

  case "${_PROBED_STATUS}" in
    running)
      _STATUS=On
      ;;
    poweredOn)
      _STATUS=On
      ;;
     up)
      _STATUS=On
      ;;
    shutoff)
      _STATUS=Off
      ;;
    poweredOff)
      _STATUS=Off
      ;;
    down)
      _STATUS=Off
      ;;
    *)
      echo "can not parse power status, please review $0"
  esac

  if [[ ${_STATUS} == 'On' ]]; then
    ssh -q -l ${PUSH_USER} -i ${RSA_ID} ${SATELLITE} \
        "hammer host stop --id $I"
    sleep 10
    ssh -q -l ${PUSH_USER} -i ${RSA_ID} ${SATELLITE} \
        "hammer host start --id $I"
  elif [[ ${_STATUS} == 'Off' ]]; then
    ssh -q -l ${PUSH_USER} -i ${RSA_ID} ${SATELLITE} \
        "hammer host start --id $I"
  else
    err "Host $I is neither running nor shutoff. No action possible!"
    exit 1
  fi
done
