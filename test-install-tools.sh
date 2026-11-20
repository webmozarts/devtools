#!/usr/bin/env bash
# Tests install-tools.sh on the Claude Code cloud environments' platform: a plain
# Ubuntu 24.04 container with Node under /opt/node<major>, where the cloud image ships
# it. The docker-sandbox image build covers the Debian side.
#
# Run it as root in a throwaway container, never on your machine, e.g.:
#   docker run --rm --volume "$PWD:/src:ro" ubuntu:24.04 /src/test-install-tools.sh
set -euo pipefail

dir="$(dirname "$0")"
script="${dir}/install-tools.sh"
node_major="$(sed -n 's/^NODE_MAJOR=//p' "${script}")"
node_dir="/opt/node${node_major}"

assert_node_link() {
    if [ "$(readlink /opt/node)" != "${node_dir}" ]; then
        echo "test-install-tools: /opt/node does not link to ${node_dir}" >&2
        exit 1
    fi
}

mkdir -p "${node_dir}/bin"
printf '#!/bin/sh\necho v%s.0.0\n' "${node_major}" > "${node_dir}/bin/node"
chmod +x "${node_dir}/bin/node"

bash "${script}"
assert_node_link

# The second run must find every tool in place. With every proxy pointing at a closed
# port, any download or `apt-get update` it still attempts fails the test. It must also
# repair a link that points to the wrong place.
ln -sfn /opt/node-wrong /opt/node
dead_proxy=http://127.0.0.1:9
http_proxy="${dead_proxy}" https_proxy="${dead_proxy}" \
    HTTP_PROXY="${dead_proxy}" HTTPS_PROXY="${dead_proxy}" \
    bash "${script}"
assert_node_link

hash -r
parallel --version | grep -q '^GNU parallel'
for tool in just glab yq aws ansible yamllint jq psql; do
    "${tool}" --version >/dev/null
done
sbx version >/dev/null

echo "install-tools.sh: OK"
