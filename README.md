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

Qwen3.8-27B-NVFP4 needs a GPU with native FP4 (NVIDIA Blackwell, for example the RTX PRO 6000 of the
AWS `g7e` instances). On older GPUs vLLM falls back to slower kernels.

Each `Containerfile` downloads the files from Hugging Face at a fixed commit and checks their sha256.
Every large file is its own layer, so CRI-O pulls the layers in parallel.

## Release

Quay builds the images. Each model directory has its own Quay repository with a build trigger on
this GitHub repo, like the `router` and `presidio` images. Nobody needs Quay credentials to use an
image: the repositories are public, and a new cluster pulls them anonymously.

1. Merge the change on `main`. The CI must be green.
2. Create and push a tag `<model directory>-<first 7 characters of the Hugging Face commit>`:

   ```bash
   git tag qwen38-27b-nvfp4-d23c6ff
   git push origin qwen38-27b-nvfp4-d23c6ff
   ```

3. Quay builds `<model directory>/Containerfile` and publishes
   `quay.io/sovereign-selfheal/modelcar-<model directory>:<tag>`. The build downloads the model
   from Hugging Face, so it takes a while (tens of minutes for 25 GB).
4. Pin the digest in the `gitops` repo (`bootstrap/values.yaml`, `localModel.profiles.gpu.storageUri`)
   and in the `ansible` repo (`roles/model_prepull/defaults/main.yml`), with the comment
   `# tag <tag>, resolved on quay.io on <date>`. Open the PRs.

Never move or reuse a tag. To read the digest of a tag:

```bash
oc image info quay.io/sovereign-selfheal/modelcar-qwen38-27b-nvfp4:qwen38-27b-nvfp4-d23c6ff
```

### Quay setup (once per model)

1. Create the repository `quay.io/sovereign-selfheal/modelcar-<model directory>`, public.
2. Add a build trigger on the GitHub repository `sovereign-selfheal/modelcar`:
   - Dockerfile: `/<model directory>/Containerfile`; context: `/<model directory>`;
   - only tags that match `refs/tags/<model directory>-.*`;
   - tag the image with the git tag name.

### Fallback: build on OpenShift

If a model is too large for the Quay builders (disk or time limit), build it on an OpenShift
cluster (Build capability enabled) and push it with a Quay robot account. The build pod needs
about 2.5 times the model size of local disk (70 GiB for 25 GB).

```bash
oc create namespace modelcar-build
oc -n modelcar-build create secret docker-registry quay-push \
  --docker-server=quay.io --docker-username='<robot name>' --docker-password='<robot token>'
scripts/build-on-openshift.sh qwen38-27b-nvfp4 qwen38-27b-nvfp4-d23c6ff   # prints the digest
oc delete namespace modelcar-build
```

## Add a model

1. Create `<model>/Containerfile` from an existing one. Pin the Hugging Face commit and the sha256 of every
   file. For large files the sha256 is the LFS object id of the Hugging Face API:
   `curl -s https://huggingface.co/api/models/<org>/<model>/tree/<commit>`. For small files, download
   them and run `sha256sum`.
2. Keep one `ADD` per large file.
3. Open a PR, set up Quay for the new directory, then tag and pin as above.

## License

Apache License 2.0. The models keep their own licenses (Qwen3.8: Apache 2.0).
