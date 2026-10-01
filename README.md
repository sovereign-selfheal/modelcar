# modelcar: model images for KServe

Modelcar images of the local models of the demo *The Sovereign, Self-Healing Platform*. A modelcar is
an OCI image that holds only the model files. KServe mounts it into the vLLM pod
(`storageUri: oci://...`), so the model comes from a container registry like any other image, and the
GPU nodes can pre-pull it. Read [`AGENTS.md`](AGENTS.md) before changing anything.

> **Support status:** these are custom images built by the customer from public model files. The
> models are the Red Hat AI quantized models on Hugging Face (`RedHatAI/...`).

## Images

| Directory | Image | Model | Size |
|---|---|---|---|
| `qwen38-27b-nvfp4` | `quay.io/sovereign-selfheal/modelcar-qwen38-27b-nvfp4` | [RedHatAI/Qwen3.8-27B-NVFP4](https://huggingface.co/RedHatAI/Qwen3.8-27B-NVFP4) at commit `d23c6ff` | 24.7 GB |
| `diffusiongemma-26b-a4b-fp8` | `quay.io/sovereign-selfheal/modelcar-diffusiongemma-26b-a4b-fp8` | [RedHatAI/diffusiongemma-26B-A4B-it-FP8-dynamic](https://huggingface.co/RedHatAI/diffusiongemma-26B-A4B-it-FP8-dynamic) at commit `3b3dae4` | 27.2 GB |

Qwen3.8-27B-NVFP4 needs a GPU with native FP4 (NVIDIA Blackwell, for example the RTX PRO 6000 of the
AWS `g7e` instances). On older GPUs vLLM falls back to slower kernels.

Step-by-step build guide for this image: [`docs/build-qwen38-27b-nvfp4.md`](docs/build-qwen38-27b-nvfp4.md).

DiffusionGemma 26B-A4B FP8-dynamic is the decision model of the demo (vLLM structured-read mode). It
needs a GPU with native FP8 (for example the L40S of the AWS `g6e` instances). Build guide:
[`docs/build-diffusiongemma-26b-a4b-fp8.md`](docs/build-diffusiongemma-26b-a4b-fp8.md).

Each `Containerfile` downloads the files from Hugging Face at a fixed commit and checks their sha256.
Every large file is its own layer, so CRI-O pulls the layers in parallel.

## Release

The images are built on an OpenShift cluster (Build capability enabled) and pushed to Quay with
a robot account. This is a release step, done once per model version. Nobody needs Quay
credentials to use an image: the repositories are public, and a new cluster pulls them
anonymously.

Why not a Quay build trigger, like the `router` and `presidio` images? On 2026-09-28 the trigger
of `qwen38-27b-nvfp4` failed three times in a row in the `unpacking` phase with an internal error,
with the context in the model directory and at `/`, and Quay then disabled it. The Quay logs show
no cause. The same `Containerfile` builds on OpenShift.

1. Merge the change on `main`. The CI must be green. Create and push a git tag
   `<model directory>-<first 7 characters of the Hugging Face commit>` on that commit.
2. Once per model: create the repository `quay.io/sovereign-selfheal/modelcar-<model directory>`
   (public) and a robot account with write access to it.
3. Log in to the cluster with `oc`, create the push Secret, run the build (same tag as git), then
   delete the namespace. The build needs about 3 times the model size of free disk above the
   eviction threshold (80 GB for 25 GB): run it on a GPU node with `BUILD_NODE`. It takes about
   35 minutes for 25 GB. Details and measurements: [`docs/build-qwen38-27b-nvfp4.md`](docs/build-qwen38-27b-nvfp4.md).

   ```bash
   oc create namespace modelcar-build
   oc -n modelcar-build create secret docker-registry quay-push \
     --docker-server=quay.io --docker-username='<robot name>' --docker-password='<robot token>'
   BUILD_NODE=<gpu node> scripts/build-on-openshift.sh qwen38-27b-nvfp4 qwen38-27b-nvfp4-d23c6ff   # prints the digest
   oc delete namespace modelcar-build
   ```

4. Pin the digest in the `gitops` repo (`bootstrap/values.yaml`, `localModel.profiles.gpu.storageUri`)
   and in the `ansible` repo (`roles/model_prepull/defaults/main.yml`), with the comment
   `# tag <tag>, resolved on quay.io on <date>`. Open the PRs.

Never move or reuse a tag. To read the digest of a tag:

```bash
oc image info quay.io/sovereign-selfheal/modelcar-qwen38-27b-nvfp4:qwen38-27b-nvfp4-d23c6ff
```

## Add a model

1. Create `<model>/Containerfile` from an existing one. Pin the Hugging Face commit and the sha256 of every
   file. For large files the sha256 is the LFS object id of the Hugging Face API:
   `curl -s https://huggingface.co/api/models/<org>/<model>/tree/<commit>`. For small files, download
   them and run `sha256sum`.
2. Keep one `ADD` per large file.
3. Open a PR, then build and pin as above.

## License

Apache License 2.0. The models keep their own licenses (Qwen3.8: Apache 2.0).
