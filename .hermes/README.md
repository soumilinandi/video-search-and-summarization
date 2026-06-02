# VSS Hermes

Standalone Hermes support for NVIDIA Video Search & Summarization.

This is the non-sandboxed path. Hermes runs on the VSS host and uses this
repository's project context plus VSS skills directly.

## What This Repo Provides

- `.hermes.md` — project context that Hermes auto-discovers when launched from
  the repo root.
- `skills/` — VSS skills that can be registered with Hermes through
  `skills.external_dirs`.
- `.hermes/config.example.yaml` — the config block to merge into the user's
  Hermes config.

## Setup

Install and initialize Hermes:

```bash
hermes setup --portal
```

Use any other Hermes-supported provider setup if you are not using Nous Portal.

Register the VSS skills in the user's Hermes config:

```bash
hermes config edit
```

Merge in the block from `.hermes/config.example.yaml`, replacing the placeholder
with this checkout's absolute path:

```yaml
skills:
  external_dirs:
    - /path/to/video-search-and-summarization/skills
```

Then start Hermes from the VSS repo root:

```bash
hermes
```

Hermes will load `.hermes.md` as project context and discover the VSS skills
from `skills.external_dirs`.

### Optional OpenClaw Migration

This is not required for VSS skills. The VSS skills live in this repository's
top-level `skills/` directory and are registered through `skills.external_dirs`.

Use OpenClaw migration only when the user wants to bring compatible existing
OpenClaw user data into Hermes:

```bash
hermes claw migrate --dry-run
hermes claw migrate --preset user-data --skill-conflict rename
```

Use full migration only when the user also wants compatible provider secrets:

```bash
hermes claw migrate --preset full --migrate-secrets --yes
```

## First Prompts

```text
Use the vss-deploy-profile skill. Check prerequisites for the base profile, but do not deploy yet.
```

```text
Prepare a dry-run for the VSS base profile. Stop before docker compose up.
```
