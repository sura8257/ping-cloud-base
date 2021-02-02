#!/usr/bin/env sh

${VERBOSE} && set -x

. "${HOOKS_DIR}/utils.lib.sh"
. "${HOOKS_DIR}/util/upload-csd-s3-utils.sh"

# Set PATH - since this is executed from within the server process, it may not have all we need on the path
export PATH="${PATH}:${SERVER_ROOT_DIR}/bin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${JAVA_HOME}/bin"

# Allow overriding the log archive URL with an arg
test ! -z "${1}" && LOG_ARCHIVE_URL="${1}"
beluga_log "Uploading to location ${LOG_ARCHIVE_URL}"

# Set required environment variables for skbn
initializeSkbnConfiguration "${LOG_ARCHIVE_URL}"

if ! cd "${OUT_DIR}"; then
  beluga_log "Failed to chdir to: ${OUT_DIR}"
  exit 1
fi

# PDO-1812 - Inspect the filesystem for orphaned zip files from previous runs
existing_zips=$(find "${SERVER_ROOT_DIR}/bin/" -name "support-data-*.zip")
if ! test -z "${existing_zips}"; then
  beluga_log "Found these orphaned zip files from previous runs:" "WARN"
  for entry in ${existing_zips}
  do
    beluga_log "$entry" "WARN"
  done
fi

# Calling collect-support-data.sh to produce a zip of diagnostic info is pretty straightforward.
# However, unit testing this script via shunit2 is a bit trickier.  First, collect-support-data.sh
# doesn't exist on the test machine.  It's put onto the filesystem at runtime.  Consequently,
# when the unit tests run, the shell can't resolve the path to the script and so it exits
# immediately with a 'command not found' error before the test can finish.  Attempts to isolate
# the call in a util script and mock around via in the test didn't work.  The hacky workaround
# is to assign the full command to an alias and then mock the alias in the test.
beluga_log "Executing script: ${SERVER_ROOT_DIR}/collect-support-data"
alias collect-data="collect-support-data --duration 1h"

# Execute in a subshell to remove the collect-support-data.sh script output from normal logging.
# For PingDirectory, the collect-support-data script always returns a 1.  So, we can't switch
# on the return code to exit if there's a problem with the script.
collect_support_data_output=$(collect-data)
unalias collect-data

# Find the generated zip file
support_data_filename=$(find . -name support\*zip -type f | sort | tail -1)
if test -z "${support_data_filename}"; then
  beluga_log "Unable to find the support-data zip file.  Disregard this message if the pod is not up yet." "WARN"
  exit 1
else
  support_data_size=$(stat -c %s "${support_data_filename}")
  if test ${support_data_size} -eq 0; then
    beluga_log "The support-data zip file size was 0 bytes.  Disregard this message if the pod is not up yet." "WARN"
    exit 1
  fi
fi

trimmed_filename=$(basename "${support_data_filename}" .zip)

# pdo-1388 - Convert the generated zip file name to the format:
#
#  YYYYMMDDHHMM-<pod name>-support-data.zip
#
processed_filename=$(transform_csd_filename ${trimmed_filename})
if ! test -z "${processed_filename}"; then

    # Use the absolute path to the generated zip file
    src_file="${OUT_DIR}/$(basename "${support_data_filename}")"

    beluga_log "Copying: ${SKBN_K8S_PREFIX}/${src_file} to ${SKBN_CLOUD_PREFIX}/${SKBN_K8S_PREFIX}/${src_file}"

    # Copy the generated zip file to the s3 bucket and rename it
    if ! skbnCopy "${SKBN_K8S_PREFIX}/${src_file}" "${SKBN_CLOUD_PREFIX}/${processed_filename}"; then
        exit 1
    fi

    # Remove the CSD file so it is doesn't fill up the server's filesystem.
    beluga_log "Removing: ${support_data_filename}"
    rm -f "${support_data_filename}"

    if test $? -eq 0; then
      beluga_log "${support_data_filename} removed successfully"
    else
      beluga_log "There was a problem removing ${support_data_filename}.  Remove exiting with: $?" "ERROR"
      exit 1
    fi

    # Print the filename so callers can figure out the name of the CSD file that was uploaded.
    echo ${processed_filename}
else
    beluga_log "There was a problem processing the generated support data file name." "WARN"
    beluga_log "The file name is expected to be in the format: support-data-ds-8.1.0.1-pingdirectory-0-20200903203030Z" "WARN"
    beluga_log "However, the input was: ${trimmed_filename}" "WARN"
    beluga_log "Exiting with a 1"

    exit 1
fi
