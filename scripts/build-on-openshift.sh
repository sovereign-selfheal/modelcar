#!/usr/bin/env bash
# Build one modelcar on an OpenShift cluster and push it to Quay.
#
# Usage: scripts/build-on-openshift.sh <model-dir> <tag>
#   scripts/build-on-openshift.sh qwen38-27b-nvfp4 qwen38-27b-nvfp4-d23c6ff
#
# Needs: `oc` logged in to the cluster, and in the namespace $NAMESPACE (default
# modelcar-build) a Secret $PUSH_SECRET (default quay-push) of type
# kubernetes.io/dockerconfigjson that can push to the Quay repository (a Quay robot account).
# The script creates the namespace if it is missing, but never the Secret.
#
# Disk: the build needs about 3 times the model size of free local disk, above the kubelet
# eviction threshold (80 GB for a 25 GB model). A default worker (120 GiB root disk) is not enough:
# the pod was evicted there. Set BUILD_NODE to the name of a node with more free disk, for example
# a GPU node (200 GiB root disk). The script then pins the build to that node and lets the pods of
# the namespace tolerate the nvidia.com/gpu taint.
#
# At the end it prints the digest to pin in the gitops and ansible repos.
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <model-dir> <tag>" >&2
  exit 2
fi

model="$1"
tag="$2"
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
namespace="${NAMESPACE:-modelcar-build}"
push_secret="${PUSH_SECRET:-quay-push}"
repository="${REPOSITORY:-quay.io/sovereign-selfheal/modelcar-${model}}"

if [[ ! -f "${repo_dir}/${model}/Containerfile" ]]; then
  echo "No Containerfile in ${repo_dir}/${model}" >&2
  exit 2
fi

oc get namespace "${namespace}" >/dev/null 2>&1 || oc create namespace "${namespace}"

if [[ -n "${BUILD_NODE:-}" ]]; then
  # BuildConfig has no tolerations field: a default toleration of the namespace covers the build pod.
  oc annotate namespace "${namespace}" --overwrite \
    'scheduler.alpha.kubernetes.io/defaultTolerations=[{"key":"nvidia.com/gpu","operator":"Exists","effect":"NoSchedule"}]'
fi

if ! oc -n "${namespace}" get secret "${push_secret}" >/dev/null 2>&1; then
  cat >&2 <<EOF
Secret ${push_secret} not found in ${namespace}. Create it from the Quay robot account:
  oc -n ${namespace} create secret docker-registry ${push_secret} \\
    --docker-server=quay.io --docker-username='<robot name>' --docker-password='<robot token>'
EOF
  exit 1
fi

# Build for the cluster architecture: the model nodes are x86_64.
oc process -f "${repo_dir}/openshift/buildconfig.yaml" \
  -p MODEL="${model}" -p TAG="${tag}" -p REPOSITORY="${repository}" -p PUSH_SECRET="${push_secret}" \
  | oc -n "${namespace}" apply -f -

if [[ -n "${BUILD_NODE:-}" ]]; then
  oc -n "${namespace}" patch bc "modelcar-${model}" --type=merge \
    -p "{\"spec\":{\"nodeSelector\":{\"kubernetes.io/hostname\":\"${BUILD_NODE}\"}}}"
else
  oc -n "${namespace}" patch bc "modelcar-${model}" --type=json -p '[{"op":"remove","path":"/spec/nodeSelector"}]' 2>/dev/null || true
fi

build="$(oc -n "${namespace}" start-build "modelcar-${model}" --from-dir="${repo_dir}/${model}" -o name)"
echo "Started ${build}; following the log."
# The log stream can drop on a long build; the loop below waits for the real end.
oc -n "${namespace}" logs -f "${build}" || true

while true; do
  phase="$(oc -n "${namespace}" get "${build}" -o jsonpath='{.status.phase}')"
  case "${phase}" in
    Complete) break ;;
    Failed|Error|Cancelled)
      echo "Build ${build} ended in phase ${phase}" >&2
      exit 1
      ;;
    *) sleep 30 ;;
  esac
done

digest="$(oc -n "${namespace}" get "${build}" -o jsonpath='{.status.output.to.imageDigest}')"
echo
echo "Pushed ${repository}:${tag}"
echo "Digest: ${digest}"
echo "Pin:    oci://${repository}@${digest}"
