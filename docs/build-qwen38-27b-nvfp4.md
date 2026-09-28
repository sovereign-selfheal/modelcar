# Build the Qwen3.8-27B-NVFP4 modelcar

This guide explains how to build and publish the modelcar image of
[RedHatAI/Qwen3.8-27B-NVFP4](https://huggingface.co/RedHatAI/Qwen3.8-27B-NVFP4), the local model of
the demo, and how to pin it in the other repositories. It describes the build of 2026-09-28; the
times in it were measured then.

You need this guide only to publish a **new** version of the image. To deploy the demo on a new
cluster you need nothing from here: the image is public, and the cluster pulls it without
credentials.

## 1. What the image contains

| Item | Value |
|---|---|
| Image | `quay.io/sovereign-selfheal/modelcar-qwen38-27b-nvfp4` (public) |
| Tag | `qwen38-27b-nvfp4-d23c6ff` (git tag and image tag are the same) |
| Digest | `sha256:07490ed7b3ebbd8105de41712a61a3b206c862afdd48a60e7fde0b1f3a249661` |
| Model | `RedHatAI/Qwen3.8-27B-NVFP4`, Hugging Face commit `d23c6ff198a005532746610e9d719c9f6d27a2b1` |
| Base image | `registry.access.redhat.com/ubi9/ubi-micro` 9.8, pinned by digest |
| Size | 24.19 GB in 12 layers: the base, 8 small files, 3 weight files (0.84, 3.8 and 19.5 GB) |

The model is Qwen3.8 27B, quantized by Red Hat AI with NVFP4: FP4 for the MLP weights, FP8 for the
attention weights and the KV cache. It needs a GPU with native FP4, that is NVIDIA Blackwell. In the
demo this is one RTX PRO 6000 (96 GB) of an AWS `g7e` instance. On older GPUs vLLM falls back to
slower kernels, so do not use this image there.

The [`Containerfile`](../qwen38-27b-nvfp4/Containerfile) downloads every file from Hugging Face at
the fixed commit, and `ADD --checksum` checks its sha256. The three weight files (0.85 GB, 3.9 GB and
20 GB) each get their own layer, so CRI-O can pull them in parallel.

## 2. Prerequisites

- An OpenShift 4.22 cluster with the Build capability (`oc api-resources | grep buildconfigs`).
- A node with about **80 GB of free disk above the eviction threshold**. See section 3, "Disk".
  A default worker of the demo clusters (120 GiB root disk) is **not** enough; a GPU node (200 GiB
  root disk) is.
- Outbound access from the cluster to `huggingface.co` (and its CDN) and to `quay.io`.
- `oc` logged in as a user who can create a namespace, a BuildConfig and a Secret.
- The Quay repository `sovereign-selfheal/modelcar-qwen38-27b-nvfp4` (public) and a Quay robot
  account with **write** access to it.
- A clone of this repository at the git tag you release.

## 3. Build and push

1. Check out the tag you release. The build uploads the files of your working copy, not the tag:

   ```bash
   git fetch --tags
   git checkout qwen38-27b-nvfp4-d23c6ff
   ```

2. Check the robot token before you use it. The answer must list `push` for the repository:

   ```bash
   curl -s -u 'sovereign-selfheal+<robot>:<token>' \
     'https://quay.io/v2/auth?service=quay.io&scope=repository:sovereign-selfheal/modelcar-qwen38-27b-nvfp4:push,pull' \
     | python3 -c 'import json,sys,base64; t=json.load(sys.stdin)["token"].split(".")[1]; print(json.loads(base64.urlsafe_b64decode(t+"=="))["access"])'
   ```

3. Create the namespace and the push Secret. The token stays in the cluster; never commit it.

   ```bash
   oc create namespace modelcar-build
   oc -n modelcar-build create secret docker-registry quay-push \
     --docker-server=quay.io \
     --docker-username='sovereign-selfheal+<robot>' --docker-password='<token>'
   ```

4. Pick the node for the build (see "Disk" below) and run the build:

   ```bash
   oc get nodes -l node-role.kubernetes.io/gpu
   BUILD_NODE=<gpu node name> scripts/build-on-openshift.sh qwen38-27b-nvfp4 qwen38-27b-nvfp4-d23c6ff
   ```

   With `BUILD_NODE` the script pins the build pod to that node, and gives the namespace a default
   toleration for the `nvidia.com/gpu` taint (a BuildConfig has no tolerations field). The script creates the BuildConfig from [`openshift/buildconfig.yaml`](../openshift/buildconfig.yaml),
   uploads the model directory, follows the log and waits for the end. It prints the digest:

   ```text
   Pushed quay.io/sovereign-selfheal/modelcar-qwen38-27b-nvfp4:qwen38-27b-nvfp4-d23c6ff
   Digest: sha256:...
   Pin:    oci://quay.io/sovereign-selfheal/modelcar-qwen38-27b-nvfp4@sha256:...
   ```

   Measured on 2026-09-28 (OCP 4.22.14 in us-east-2, build pod on the `g7e.4xlarge` GPU node,
   200 GiB gp3 root disk with the default 125 MB/s):

   | Phase | Time |
   |---|---|
   | Small files, `model_mtp` (0.85 GB) and `model-00002` (3.9 GB) | about 4 min |
   | `model-00001` (20 GB) | about 22 min |
   | Push to Quay | about 9 min |
   | Total | 34 min 38 s |

   **Disk.** Buildah on OpenShift uses overlay *without native diff*. For each layer it copies the
   files to compute the difference, so the 20 GB file needs about 4 times its size while its `ADD`
   runs: the download, the copy into the layer, the diff, the blob for the push. The free disk of the
   node went from 154 GB to 40 GB, then back to 104 GB when the step ended. The kubelet evicts pods
   when the free disk falls below 15% (image file system) or 10% (node file system). A first build on
   an `m6a.4xlarge` worker (76 GB free, eviction below 16 GB) was evicted in this step.
   The disk, not the network, sets the speed: about 70 MB/s of writes during the large step.

   If the log stream stops, the script keeps waiting for the build phase. To look at the build from
   another terminal: `oc -n modelcar-build get builds` and `oc -n modelcar-build logs -f build/<name>`.

5. Delete the namespace. This also deletes the Secret with the token:

   ```bash
   oc delete namespace modelcar-build
   ```

6. If the token was shared outside the cluster (for example in a chat), regenerate it in Quay.

## 4. Check the image

```bash
oc image info quay.io/sovereign-selfheal/modelcar-qwen38-27b-nvfp4:qwen38-27b-nvfp4-d23c6ff
```

- The digest must be the one printed by the script.
- The image must have one layer per `ADD`: the base layer, 8 small files, 3 large layers.
- An anonymous pull must work (the repository is public). Log out of quay.io first, or use a clean
  machine.

## 5. Pin the digest

The demo never follows a tag. Pin the digest in two repositories, in the same change set:

- `gitops`, `bootstrap/values.yaml`, `localModel.profiles.gpu.storageUri`:

  ```yaml
  # tag qwen38-27b-nvfp4-d23c6ff, resolved on quay.io on <date>
  storageUri: oci://quay.io/sovereign-selfheal/modelcar-qwen38-27b-nvfp4@sha256:<digest>
  ```

- `ansible`, `roles/model_prepull/defaults/main.yml`, `model_prepull_images.gpu.modelcar` (same digest,
  without `oci://`). If the two digests differ, the pre-pull downloads an image that nobody uses; the
  seed prints a warning.

## 6. Known problems

- **Quay build trigger.** The first plan was a Quay build trigger, like the `router` and `presidio`
  images. On 2026-09-28 the trigger failed three times in a row in the `unpacking` phase with an
  internal error, with the context in the model directory and at `/`. Quay then disabled the
  trigger. The logs show no cause. The build on OpenShift works with the same `Containerfile`.
- **Build disk.** For a larger model, a GPU node will not be enough either. Two options, not built
  yet: a dedicated build node (a cheap instance type with a 500 GiB gp3 root disk and a higher
  throughput, created for the build and scaled to 0 after it, pinned with `BUILD_NODE`), or a Job
  with buildah and a generic ephemeral volume of 200-300 GiB on `/var/lib/containers` (needs a
  privileged pod). The build node keeps the BuildConfig as it is, so it is the preferred option.
- **GPU capacity.** On 2026-09-28 AWS had no `g7e.2xlarge` capacity in any zone of us-east-2, and
  `g7e.4xlarge` only in us-east-2a after about 20 minutes. This does not affect the build (it runs on
  a CPU worker), but it affects every test of the image. Check the capacity before a demo.
- **Hugging Face changes.** The `Containerfile` pins the commit and the checksums. If Red Hat AI
  publishes a new revision, update the commit, the checksums and the tag together (see the README,
  "Add a model"). A wrong checksum stops the build at that `ADD`.
