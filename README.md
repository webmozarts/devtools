# devtools

`install-tools.sh` installs the general-purpose tools that every Webmozarts Claude Code
session uses: just, glab, yq, the sbx CLI, the AWS CLI, Ansible, a Postgres client, Node
and more. The versions are pinned at the top of the script.

Two places run it, so both get the same tools at the same versions:

- the baseline image of [docker-sandbox](https://gitlab.webmozarts.com/webmozarts/libraries/docker-sandbox),
  on Debian;
- the setup script of the Claude Code cloud environments, on Ubuntu.

## How it runs

The script runs as root. It runs more than once on the same machine: the cloud runs it at
every session start. So it skips each tool that is already in place, and a second run
downloads nothing.

## How the image and the cloud get it

Both download the script from the public GitHub mirror of this repository,
[`webmozarts/devtools`](https://github.com/webmozarts/devtools), at `main`:

- The docker-sandbox image build resolves the commit of `main` and downloads the script
  at that commit:

  ```bash
  git ls-remote https://github.com/webmozarts/devtools.git refs/heads/main
  ```

- The cloud setup script downloads it from `main` directly:

  ```bash
  curl --proto '=https' --tlsv1.2 -fsSL --retry 3 --connect-timeout 20 --max-time 60 \
      https://raw.githubusercontent.com/webmozarts/devtools/refs/heads/main/install-tools.sh \
      -o /tmp/install-tools.sh
  bash /tmp/install-tools.sh
  ```

Always write `refs/heads/main`, not a bare `main`. A bare `main` resolves to a tag named
`main` first, if someone ever creates one.

The full setup of a cloud environment, with its log and troubleshooting, is documented
in Notion: [Claude Code Cloud Sessions](https://app.notion.com/p/41bcd75c429581c6879fcf1f2f1ac78a).

## Node in the cloud

The cloud image ships one Node build per major version under `/opt/node<major>`, and puts
an older one on PATH. In the cloud, `install-tools.sh` installs no Node. Instead, it links
`/opt/node` to `/opt/node<NODE_MAJOR>`, the major the script pins. It does that on every
run and fixes a link that points somewhere else.

docker-sandbox's `cloud-session-env.sh` relies on this link: it puts `/opt/node/bin`
first on PATH when it exists. Keep the link when you change the script.

## Changing the script

`main` is what every new image and every new cloud environment installs. So a change on
`main` goes live for everyone. `main` is protected: open a merge request, and get it
reviewed before it is merged.

CI runs `test-install-tools.sh` on Ubuntu 24.04. You can run it yourself as root in a
throwaway container, never on your machine:

```bash
docker run --rm --volume "$PWD:/src:ro" ubuntu:24.04 /src/test-install-tools.sh
```
