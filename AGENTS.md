# AGENTS.md: `modelcar` repository

Guidance for AI coding agents and humans working in this repo. Read it fully before you change anything.

## 1. Purpose

This repository builds the **modelcar images** of the local models of the demo *The Sovereign,
Self-Healing Platform*. A modelcar is an OCI image that holds only the model files under `/models`.
KServe mounts it into the vLLM pod (`storageUri: oci://...`), and the `ansible` repo pre-pulls it on
the GPU nodes. This repo contains no Kubernetes manifests of the demo.

We build our own modelcar only when no ready image exists (Red Hat's `registry.redhat.io/rhai` or
`quay.io/redhat-ai-services/modelcar-catalog`). Prefer a ready image when there is one.

## 2. Contract with the `gitops` and `ansible` repos

| Owner | Items |
|---|---|
| `modelcar` (this repo) | One directory per model with its `Containerfile`, the pinned model revision and checksums, the image tags |
| `gitops` | The `storageUri` digest in `bootstrap/values.yaml` (`localModel.profiles`), the vLLM arguments |
| `ansible` | The pre-pull digest in `roles/model_prepull/defaults/main.yml` (same digest as `gitops`), the GPU node type |

The image offers this interface:

- Model files in `/models`, readable by any UID. vLLM reads them from `/mnt/models`.
- A shell (`sh`): KServe starts the modelcar container with a shell command.
- The image ends with a non-root `USER`.

## 3. Layout

```
<model>/Containerfile           # one directory per model; files from Hugging Face at a fixed commit
openshift/buildconfig.yaml      # fallback only: binary Docker BuildConfig that pushes to Quay
scripts/build-on-openshift.sh   # fallback only: runs that build on a cluster, prints the digest
.github/workflows/ci.yml        # lint only (the images are too large for the CI runners)
```

## 4. Conventions

- **Pins**: the base image by digest, the model by Hugging Face commit, and every file by sha256
  (`ADD --checksum`). A comment says where and when each pin was resolved.
- **One layer per large file**, so that CRI-O pulls the layers in parallel.
- **Quay builds the images** from git tags (one build trigger per model directory). This repo
  pushes nothing. If a model is too large for the Quay builders, build it on OpenShift instead
  (`scripts/build-on-openshift.sh`, see README), never on a laptop: a model is tens of GB.
- **Tags**: `<model directory>-<first 7 characters of the Hugging Face commit>`, for example
  `qwen38-27b-nvfp4-d23c6ff`. The git tag and the image tag are the same. Never move, delete or
  reuse a tag. `gitops` never follows a tag.
- Comments, docs and commit messages in **English**, level B2/C1: short, clear sentences, no idioms.
- **Python tools with uv** (`uvx`, `uv run --with`), never pip on the host.

## 5. Release of a model image

1. Merge the new or changed `<model>/Containerfile` on `main` with a green CI.
2. Tag `<model directory>-<commit>` and push the tag. The Quay build trigger of that model builds
   it and publishes `quay.io/sovereign-selfheal/modelcar-<model directory>:<tag>`.
3. PR on `gitops` (`storageUri` by digest, `# tag <tag>, resolved on quay.io on <date>`) and on `ansible`
   (`model_prepull_images`, same digest).

## 6. Before you open a PR

```bash
uvx yamllint .
shellcheck scripts/*.sh
hadolint */Containerfile
```

## 7. Out of scope

- InferenceService, ServingRuntime, vLLM arguments → `gitops` repo.
- GPU nodes, pre-pull DaemonSets → `ansible` repo.

## 8. When in doubt

- Ask before changing a model revision or the base image of an image in use.
