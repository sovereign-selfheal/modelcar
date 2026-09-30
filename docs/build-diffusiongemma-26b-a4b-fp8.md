# Build the DiffusionGemma 26B-A4B FP8-dynamic modelcar

This guide explains how to build and publish the modelcar image of
[RedHatAI/diffusiongemma-26B-A4B-it-FP8-dynamic](https://huggingface.co/RedHatAI/diffusiongemma-26B-A4B-it-FP8-dynamic),
the decision model of the demo. It describes the build of 2026-09-30; the times in it were measured then.
The steps are the same as in [`build-qwen38-27b-nvfp4.md`](build-qwen38-27b-nvfp4.md); this guide lists
only what is different.

You need this guide only to publish a **new** version of the image. To deploy the demo you need nothing
from here: the image is public.

> **Support status:** the image holds public model files. The decision model runs on an unsupported
> preview vLLM image (`registry.redhat.io/rhaii-preview/vllm-cuda-rhel9:diffusiongemma-jev`); see the
> gitops repo, component `decision-model`.

## 1. What the image contains

| Item | Value |
|---|---|
| Image | `quay.io/sovereign-selfheal/modelcar-diffusiongemma-26b-a4b-fp8` (public) |
| Tag | `diffusiongemma-26b-a4b-fp8-3b3dae4` (git tag and image tag are the same) |
| Digest | `sha256:b10821319f60a03ec78e6aacf57bedca83e540fd8b0cbcbf3ffc644215e81fc6` |
| Model | `RedHatAI/diffusiongemma-26B-A4B-it-FP8-dynamic`, Hugging Face commit `3b3dae4697494da5a290e9c0461954449e76c4f5` |
| Base image | `registry.access.redhat.com/ubi9/ubi-micro` 9.8, pinned by digest |
| Size | 27.15 GB in 10 layers: the base, 8 small files, **one weights file of 27.14 GB** |

The model is DiffusionGemma 26B-A4B (mixture of experts: 25.8 B parameters, 3.0 B outside the experts),
quantized by Red Hat AI with FP8 (dynamic activations). It needs a GPU with native FP8: in the demo one
NVIDIA L40S (48 GB) of an AWS `g6e.2xlarge`. The tokenizer files are in the image: the decision server
reads them from the model directory. The checkpoint has no custom code (`auto_map`), so vLLM needs no
`--trust-remote-code`.

The checkpoint has a single weights file, `model.safetensors`, so the image has one large layer (the
FP8 weights do not compress: 27.20 GB of file, 27.14 GB of gzip layer). CRI-O pulls it over one
connection.

## 2. What is different from the Qwen3.8 build

**Disk.** Buildah needs about 4 times the size of the large file while its `ADD` runs (see the Qwen3.8
guide), so about 110 GB here. A GPU node of the demo (200 GiB root disk, about 147 GB free with Qwen3.8
and vLLM pulled) is **not** enough: the build would be evicted, and the Qwen node serves the demo. The
build ran on a temporary CPU node instead:

```bash
# a MachineSet cloned from a worker MachineSet: m6a.2xlarge, root disk gp3 350 GiB,
# 6000 IOPS, 500 MB/s; node label sovereign-selfheal/modelcar-build, taint nvidia.com/gpu
# (build-on-openshift.sh already adds a namespace toleration for it)
BUILD_NODE=<that node> scripts/build-on-openshift.sh diffusiongemma-26b-a4b-fp8 diffusiongemma-26b-a4b-fp8-3b3dae4
# after the build: delete the namespace modelcar-build and the MachineSet
```

Measured on 2026-09-30 (OCP 4.22.15 in us-east-2):

| Phase | Time |
|---|---|
| Node: MachineSet -> Ready | about 3 min |
| Small files | about 1 min |
| `model.safetensors` (27.2 GB): download, layer, diff | about 35 min |
| Push to Quay | about 11 min |
| Total build | 46 min 50 s (16:54:09-17:40:59 UTC) |

The free disk of the build node went from 356 GB to about 250 GB during the large step.

## 3. Pin

Pin the digest in the gitops repo (`decisionModel.storageUri` in `bootstrap/values.yaml`) and in the
ansible repo (`model_prepull_decision_images.modelcar` in `roles/model_prepull/defaults/main.yml`),
with the comment `# tag diffusiongemma-26b-a4b-fp8-3b3dae4, resolved on quay.io on 2026-09-30`.
