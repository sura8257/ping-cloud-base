#!/usr/bin/env sh

${VERBOSE} && set -x

# Set PATH - since this is executed from within the server process, it may not have all we need on the path
export PATH="${PATH}:${SERVER_ROOT_DIR}/bin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${JAVA_HOME}/bin"

# Allow overriding the log archive URL with an arg
test ! -z "${1}" && LOG_ARCHIVE_URL="${1}"
echo "Uploading to location ${LOG_ARCHIVE_URL}"

# Install AWS CLI if the upload location is S3
if test "${LOG_ARCHIVE_URL#s3}" == "${LOG_ARCHIVE_URL}"; then
  echo "Upload location is not S3"
  exit 0
elif ! which aws > /dev/null; then
  echo "Installing AWS CLI"
  apk --update add python3
  pip3 install --no-cache-dir --upgrade pip
  pip3 install --no-cache-dir --upgrade awscli
fi

FORMAT="+%d/%b/%Y:%H:%M:%S %z"
NOW=$(date "${FORMAT}")

cd "${OUT_DIR}"

collect-support-data --duration 1h
CSD_OUT=$(find . -name support\*zip -type f | sort | tail -1)

BUCKET_URL_NO_PROTOCOL=${LOG_ARCHIVE_URL#s3://}
BUCKET_NAME=$(echo ${BUCKET_URL_NO_PROTOCOL} | cut -d/ -f1)

DIRECTORY_NAME=$(echo ${PING_PRODUCT} | tr '[:upper:]' '[:lower:]')
echo "Creating directory ${DIRECTORY_NAME} under bucket ${BUCKET_NAME}"
aws s3api put-object --bucket "${BUCKET_NAME}" --key "${DIRECTORY_NAME}"/

if test "${LOG_ARCHIVE_URL}" == */pingdirectory; then
  TARGET_URL="${LOG_ARCHIVE_URL}"
else
  TARGET_URL="${LOG_ARCHIVE_URL}/${DIRECTORY_NAME}"
fi

echo "Uploading "${CSD_OUT}" to ${TARGET_URL} at ${NOW}"
DST_FILE=$(basename "${CSD_OUT}")
aws s3 cp "${CSD_OUT}" "${TARGET_URL}/${DST_FILE}"

echo "Upload return code: ${?}"

# Remove the CSD file so it is doesn't fill up the server's filesystem.
rm -f "${CSD_OUT}"

# Print the filename so callers can figure out the name of the CSD file that was uploaded.
echo "${DST_FILE}"