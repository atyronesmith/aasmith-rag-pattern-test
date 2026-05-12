#!/bin/bash
set -euo pipefail

function is_available {
  command -v "$1" >/dev/null 2>&1 || { echo >&2 "$1 is required but it's not installed. Aborting."; exit 1; }
}

function version {
    echo "$1" | awk -F. '{ printf("%d%03d%03d%03d\n", $1,$2,$3,$4); }'
}

if [ -z "${PATTERN_UTILITY_CONTAINER:-}" ]; then
	PATTERN_UTILITY_CONTAINER="quay.io/validatedpatterns/utility-container"
fi
if [ -n "${PATTERN_DISCONNECTED_HOME:-}" ]; then
    PATTERN_UTILITY_CONTAINER="${PATTERN_DISCONNECTED_HOME}/utility-container"
    PATTERN_INSTALL_CHART="oci://${PATTERN_DISCONNECTED_HOME}/pattern-install"
    echo "PATTERN_DISCONNECTED_HOME is set to ${PATTERN_DISCONNECTED_HOME}"
    echo "Setting the following variables:"
    echo "  PATTERN_UTILITY_CONTAINER: ${PATTERN_UTILITY_CONTAINER}"
    echo "  PATTERN_INSTALL_CHART: ${PATTERN_INSTALL_CHART}"
fi

readonly commands=(podman)
for cmd in "${commands[@]}"; do is_available "$cmd"; done

UNSUPPORTED_PODMAN_VERSIONS="1.6 1.5"
PODMAN_VERSION_STR=$(podman --version) || { echo "Failed to get podman version"; exit 1; }
for i in ${UNSUPPORTED_PODMAN_VERSIONS}; do
	if echo "${PODMAN_VERSION_STR}" | grep -q -E "\b${i}"; then
		echo "Unsupported podman version. We recommend > 4.3.0"
		podman --version
		exit 1
	fi
done

PODMAN_VERSION=$(echo "${PODMAN_VERSION_STR}" | awk '{ print $NF }')

PODMAN_ARGS=()
if [ "$(version "${PODMAN_VERSION}")" -lt "$(version "4.3.0")" ]; then
    PODMAN_ARGS=(-v "${HOME}:/root")
else
    MYNAME=$(id -n -u)
    MYUID=$(id -u)
    MYGID=$(id -g)
    PODMAN_ARGS=(--passwd-entry "${MYNAME}:x:${MYUID}:${MYGID}::/pattern-home:/bin/bash" --user "${MYUID}:${MYGID}" --userns "keep-id:uid=${MYUID},gid=${MYGID}")
fi

if [ -n "${KUBECONFIG:-}" ]; then
    if [[ ! "${KUBECONFIG}" =~ ^"${HOME}" ]]; then
        echo "${KUBECONFIG} is pointing outside of the HOME folder, this will make it unavailable from the container."
        echo "Please move it somewhere inside your $HOME folder, as that is what gets bind-mounted inside the container"
        exit 1
    fi
fi

REMOTE_PODMAN=$(podman system connection list | tail -n +2 | wc -l) || REMOTE_PODMAN=0
PKI_HOST_MOUNT_ARGS=()
if [ "${REMOTE_PODMAN}" -eq 0 ]; then
    if [ -d /etc/pki/tls ]; then
        PKI_HOST_MOUNT_ARGS=(-v /etc/pki:/etc/pki:ro)
    elif [ -d /etc/ssl ]; then
        PKI_HOST_MOUNT_ARGS=(-v /etc/ssl:/etc/ssl:ro)
    else
        PKI_HOST_MOUNT_ARGS=(-v /usr/share/ca-certificates:/usr/share/ca-certificates:ro)
    fi
fi

EXTRA_ARGS_ARRAY=()
if [ -n "${EXTRA_ARGS:-}" ]; then
    # shellcheck disable=SC2206
    EXTRA_ARGS_ARRAY=(${EXTRA_ARGS})
fi

podman run -it --rm --pull=newer \
    --security-opt label=disable \
    -e ANSIBLE_STDOUT_CALLBACK \
    -e DISABLE_VALIDATE_ORIGIN \
    -e EXTRA_HELM_OPTS \
    -e EXTRA_PLAYBOOK_OPTS \
    -e K8S_AUTH_HOST \
    -e K8S_AUTH_PASSWORD \
    -e K8S_AUTH_SSL_CA_CERT \
    -e K8S_AUTH_TOKEN \
    -e K8S_AUTH_USERNAME \
    -e K8S_AUTH_VERIFY_SSL \
    -e KUBECONFIG \
    -e PATTERN_DIR \
    -e PATTERN_DISCONNECTED_HOME \
    -e PATTERN_INSTALL_CHART \
    -e PATTERN_NAME \
    -e TARGET_BRANCH \
    -e TARGET_CLUSTERGROUP \
    -e TARGET_ORIGIN \
    -e TOKEN_NAMESPACE \
    -e TOKEN_SECRET \
    -e UUID_FILE \
    -e VALUES_SECRET \
    "${PKI_HOST_MOUNT_ARGS[@]}" \
    -v "$(pwd -P)":"$(pwd -P)" \
    -v "${HOME}":"${HOME}" \
    -v "${HOME}":/pattern-home \
    "${PODMAN_ARGS[@]}" \
    "${EXTRA_ARGS_ARRAY[@]}" \
    -w "$(pwd -P)" \
    "$PATTERN_UTILITY_CONTAINER" \
    "$@"
