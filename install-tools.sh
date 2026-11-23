#!/usr/bin/env bash
# Installs the general-purpose tools that every Webmozarts Claude Code session uses.
# Two places run this script, so both get the same tools at the same versions:
#
# - the build of docker-sandbox's baseline image, on Debian;
# - the setup script of the Claude Code cloud environments, on Ubuntu, at every session
#   start.
#
# See README.md for how both get this script. Runs as root. Skips each tool that is
# already in place, so a cloud session on a warm container downloads nothing. Steps that
# only make sense in the image (Chromium, PHP, the timezone, GitLab's SSH host keys) stay
# in docker-sandbox's image build.
set -euo pipefail

JUST_VERSION=1.53.0
GLAB_VERSION=1.101.0
YQ_VERSION=4.47.2
# Keep in step with the sbx that engineers run on the host.
SBX_VERSION=0.51.0
NODE_MAJOR=24

# Mirrors the "general-purpose dependencies" of the company-wide CI image
# (webmozarts/libraries/docker, alpine/Dockerfile), minus its CI-only tools and plus a
# Postgres client.
APT_PACKAGES=(
    # Used by this script itself
    ca-certificates
    curl
    gnupg
    xz-utils
    openssh-client
    jq
    yamllint
    python3
    postgresql-client
    vim
    # GNU parallel, which bats needs for `--jobs`. Not moreutils' `parallel`.
    parallel
    perl
    pigz
    rsync
    unzip
    tzdata
    ansible
    # Used by Ansible's aws_* modules and `--query` expressions
    python3-boto3
    python3-botocore
    python3-jmespath
)

# Match the CI image's collections, so playbooks resolve the same modules.
ANSIBLE_COLLECTIONS=(
    ansible.posix
    community.docker
)

export DEBIAN_FRONTEND=noninteractive

arch="$(dpkg --print-architecture)"
case "${arch}" in
    amd64) rust_arch=x86_64 ;;
    arm64) rust_arch=aarch64 ;;
    *) echo "install-tools: unsupported architecture: ${arch}" >&2; exit 1 ;;
esac

tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT

# Names the step that runs, so a log that stops shows where it stopped.
step() {
    echo "install-tools: $*"
}

# Retries transient failures, but not a 404: a version that doesn't exist should fail at
# once. A transfer that stalls (under 1 kB/s for 30 seconds) counts as transient. Always
# download to a file, never into a pipe, because a retry after a partial transfer would
# append a second copy to what the pipe already read.
fetch() {
    step "downloading $1"
    curl --proto '=https' --tlsv1.2 -fsSL --retry 3 --retry-connrefused \
        --connect-timeout 20 --speed-limit 1000 --speed-time 30 "$1" -o "$2"
}

# Succeeds when the output of a command matches a pattern, e.g.
#   output_matches '^glab 1\.101\.0 ' glab --version
# Collects the output first: piping straight into `grep -q` would let grep exit at the
# first match, and a command that prints more after it (glab's update notice) would die
# of SIGPIPE, which `pipefail` reports as a mismatch.
output_matches() {
    local pattern="$1" output
    shift
    output="$("$@" 2>/dev/null)" || true
    grep -q -- "${pattern}" <<<"${output}"
}

installed() {
    # shellcheck disable=SC2016 # ${Status} is dpkg-query's format, not a shell variable
    output_matches '^install ok installed$' dpkg-query -W -f='${Status}' "$1"
}

# Without these limits, a mirror that stops sending data stalls apt with no error until
# the cloud's setup time limit kills the script.
APT_OPTIONS=(-o Acquire::Retries=3 -o Acquire::http::Timeout=30 -o Acquire::https::Timeout=30)

apt_updated=false
apt_update() {
    local attempt
    if [ "${apt_updated}" = true ]; then
        return
    fi
    for attempt in 1 2 3; do
        step "apt-get update (attempt ${attempt} of 3)"
        # Error-Mode=any makes a list that failed to download fail the command, so it is
        # retried instead of leaving apt without that list.
        if timeout 120 apt-get "${APT_OPTIONS[@]}" -o APT::Update::Error-Mode=any update; then
            apt_updated=true
            return
        fi
    done
    echo "install-tools: apt-get update failed 3 times" >&2
    exit 1
}

missing=()
for package in "${APT_PACKAGES[@]}"; do
    if ! installed "${package}"; then
        missing+=("${package}")
    fi
done
step "apt packages"
if [ "${#missing[@]}" -gt 0 ]; then
    apt_update
    apt-get "${APT_OPTIONS[@]}" install -y "${missing[@]}"
fi

step "Node ${NODE_MAJOR}"
# Node and npm. The image installs them from the Docker Hardened Images apt repository
# its base configures, which carries one signed package per Node major. The cloud image
# ships its own build of each major under /opt/node<major> instead, so there is nothing
# to install. There, link /opt/node to the pinned major: docker-sandbox's session
# environment puts /opt/node/bin first on PATH (see README.md). `ln -T` fails rather
# than create the link inside /opt/node if that is a real directory.
if installed "nodejs-${NODE_MAJOR}"; then
    :
elif output_matches "^v${NODE_MAJOR}\." "/opt/node${NODE_MAJOR}/bin/node" --version; then
    if [ "$(readlink /opt/node)" != "/opt/node${NODE_MAJOR}" ]; then
        ln -sfnT "/opt/node${NODE_MAJOR}" /opt/node
    fi
else
    apt_update
    if ! apt-cache show "nodejs-${NODE_MAJOR}" >/dev/null 2>&1; then
        echo "install-tools: found neither nodejs-${NODE_MAJOR} in apt nor /opt/node${NODE_MAJOR}" >&2
        exit 1
    fi
    apt-get "${APT_OPTIONS[@]}" install -y "nodejs-${NODE_MAJOR}" npm
fi

step "just ${JUST_VERSION}"
if ! output_matches "^just ${JUST_VERSION}\$" just --version; then
    fetch "https://github.com/casey/just/releases/download/${JUST_VERSION}/just-${JUST_VERSION}-${rust_arch}-unknown-linux-musl.tar.gz" \
        "${tmp}/just.tar.gz"
    tar -xzf "${tmp}/just.tar.gz" -C /usr/local/bin just
fi

step "glab ${GLAB_VERSION}"
if ! output_matches "^glab ${GLAB_VERSION} " glab --version; then
    fetch "https://gitlab.com/gitlab-org/cli/-/releases/v${GLAB_VERSION}/downloads/glab_${GLAB_VERSION}_linux_${arch}.deb" \
        "${tmp}/glab.deb"
    apt_update
    apt-get install -y "${tmp}/glab.deb"
fi

step "yq ${YQ_VERSION}"
# mikefarah's yq. Ubuntu's `yq` package is a different tool with a different syntax.
if ! output_matches "version v${YQ_VERSION}\$" yq --version; then
    fetch "https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/yq_linux_${arch}" \
        "${tmp}/yq"
    install -m 0755 "${tmp}/yq" /usr/local/bin/yq
fi

step "sbx ${SBX_VERSION}"
# The CLI only: no sbx daemon runs here, so `sbx create` and friends stay on the host.
# Name the architecture in the asset: the unsuffixed tarball is amd64 only.
if ! output_matches "^sbx version v${SBX_VERSION} " sbx version; then
    fetch "https://github.com/docker/sbx-releases/releases/download/v${SBX_VERSION}/DockerSandboxes-linux-${arch}.tar.gz" \
        "${tmp}/sbx.tar.gz"
    tar -xzOf "${tmp}/sbx.tar.gz" docker-sbx/sbx > "${tmp}/sbx"
    install -m 0755 "${tmp}/sbx" /usr/local/bin/sbx
fi

step "AWS CLI"
# The AWS CLI v2 at its current release, deliberately unpinned (docker-sandbox ADR 022).
# Installed only when missing, so a warm cloud container keeps the release it first got.
#
# The installer checks the release's GPG signature, but only warns and installs anyway
# when gpg is missing. Fail instead, so a base without gpg can't turn the check off.
if ! command -v aws >/dev/null; then
    command -v gpg >/dev/null \
        || { echo "install-tools: gpg missing, the AWS CLI installer would skip signature verification" >&2; exit 1; }
    fetch https://awscli.amazonaws.com/v2/install.sh "${tmp}/aws-install.sh"
    # `--system` installs to /usr/local. Without it, the CLI lands under root's home,
    # where no other user sees it.
    bash "${tmp}/aws-install.sh" --system
fi

step "Ansible collections"
# HOME=/root, because the image sets HOME=/home/agent, and a root-owned directory left
# there breaks the agent's tools.
HOME=/root ansible-galaxy collection install "${ANSIBLE_COLLECTIONS[@]}"
