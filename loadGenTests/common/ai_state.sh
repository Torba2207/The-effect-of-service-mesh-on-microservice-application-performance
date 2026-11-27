# Sourced by the runners: where does the cluster send AI calls, and is the AI host in the mesh?
#
#   ai_state            sets AI_MODE (external | mesh) and AI_EP (the AI host address(es))
#   ai_label_check L    exits when label L does not match AI_MODE (see AI_MESH_SUFFIX)
#
# external: thesis-test/ai-service is a selector-less Service with manual Endpoints
#           (deployments/k8s/ai-service/ai-service-external.yaml) - every measurement before the
#           AI host joined meshes, and every `make <target>` without AI_MESH=1.
# mesh:     the Service selects the AI host's mesh registration (`make <target> AI_MESH=1`,
#           deployments/ansible/ai_mesh.yml); Kubernetes Endpoints are then empty by design, so
#           the address comes from the Istio WorkloadEntry.
#
# Runs that call the AI host carry AI_MESH_SUFFIX in their configuration label in mesh mode, so
# the two variants never share a run_id or a CSV row label. Runs that do not touch the AI host
# are unaffected by it and keep the plain label.
AI_MESH_SUFFIX="_aimesh"

ai_state() {
  local ns=thesis-test sel
  sel="$(kubectl --context "$CTX" -n "$ns" get svc ai-service -o jsonpath='{.spec.selector.app}' 2>/dev/null || true)"
  if [ -n "$sel" ]; then
    AI_MODE=mesh
    # The selector matches the entry's spec.labels (metadata labels may be empty).
    AI_EP="$(kubectl --context "$CTX" -n "$ns" get workloadentries.networking.istio.io \
      -o jsonpath="{.items[?(@.spec.labels.app==\"$sel\")].spec.address}" 2>/dev/null || true)"
  else
    AI_MODE=external
    AI_EP="$(kubectl --context "$CTX" -n "$ns" get endpoints ai-service \
      -o jsonpath='{range .subsets[*]}{range .addresses[*]}{.ip}{" "}{end}{end}' 2>/dev/null || true)"
  fi
  AI_EP="${AI_EP% }"
}

ai_label_check() {
  local label="$1"
  case "$AI_MODE:$label" in
    mesh:*"$AI_MESH_SUFFIX") ;;
    mesh:*)     echo "ERROR: the AI host is IN the mesh, but label '$label' lacks '$AI_MESH_SUFFIX' (it would be filed with the external-AI data)"; exit 1 ;;
    external:*"$AI_MESH_SUFFIX") echo "ERROR: the AI host is NOT in the mesh, but label '$label' ends in '$AI_MESH_SUFFIX'"; exit 1 ;;
    *) ;;
  esac
}
