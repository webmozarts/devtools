# devtools

`install-tools.sh` installs the tools every Webmozarts Claude Code session uses. The
docker-sandbox baseline image and the Claude Code cloud environments both run it. See
`README.md`.

## Conventions

- **A tool every session needs goes in `install-tools.sh`.** That keeps the image and the
  cloud in step. A step that only makes sense in the image (Chromium, PHP, the timezone)
  stays in docker-sandbox's image build.
- **`main` is protected and goes live for every new build.** Every new image and every new
  cloud environment installs the script from `main`. Change it only through a reviewed
  merge request.
- **Consumers reference `refs/heads/main`, never a bare `main`.** A bare `main` resolves
  to a tag named `main` first.
- **The script runs as root on Debian and Ubuntu, many times.** Every step must skip what
  is already in place, and a second run must download nothing. `test-install-tools.sh`
  checks this.
- **Keep the `/opt/node` link.** In the cloud the script links `/opt/node` to
  `/opt/node<NODE_MAJOR>`, and docker-sandbox's `cloud-session-env.sh` puts
  `/opt/node/bin` first on PATH. Changing that is a change in both repositories.
- **Keep this file current.** Update it whenever project structure, conventions,
  dependencies, or workflows change.
- **Comments and docs are self-contained.** Don't carry an implementation plan's
  internal step or decision IDs ("D6", "Phase E") into code comments or docs. Refer to a
  step by what it does, and link the plan or ticket if the detail matters.
- **Single source of truth.** Don't copy values that drift (tool versions, config)
  across files. Point to the canonical source instead.

## Cloud sessions

Claude Code cloud sessions clone this repository from its GitHub mirror
(`webmozarts/devtools`). Push and open merge requests on GitLab only
(`webmozarts/libraries/devtools`). A push to the mirror is lost on the next mirror run.
