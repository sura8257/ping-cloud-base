#!/bin/bash

# Source support libs referenced by the tested script
. "${PROJECT_DIR}"/profiles/aws/pingfederate/hooks/utils.lib.sh
. "${PROJECT_DIR}"/profiles/aws/pingfederate/hooks/util/upload-csd-s3-utils.sh

kubectl() {
  echo ""
}

cd() {
  echo ""
}

find() {
  echo ""
}

collect-data() {
  echo ""
}

oneTimeSetUp() {
  export HOOKS_DIR="${PROJECT_DIR}"/profiles/aws/pingfederate/hooks
  export VERBOSE=false
}

oneTimeTearDown() {
  unset HOOKS_DIR
  unset VERBOSE
}

testUploadPingFederateCsdSupportDataNameBlank() {

  script_to_test="${PROJECT_DIR}"/profiles/aws/pingfederate/hooks/82-upload-csd-s3.sh
  result=$(. "${script_to_test}")

  assertEquals "Expected an exit code of 1 but the script returned with a different code with a result of:  $result" 1 $?

  last_line=$(echo "${result}" | tail -1)
  expected_log_msg="WARN"
  assertContains "Expected '$expected_log_msg' to be in the last line in the output but it wasn't: ${last_line}" "${last_line}" "${expected_log_msg}"
}

# When arguments are passed to a script you must
# consume all of them before shunit is invoked
# or your script won't run.  For integration
# tests, you need this line.
shift $#

# load shunit
. ${SHUNIT_PATH}