# --- VARIABLES ---
INVENTORY = ansible/inventory.ini
KUBECTX   = projekt-badawchy-cluster
TEST_NS   = thesis-test
ISTIO_PA  = k8s/istio

.PHONY: clean teardown baseline istio istio-nomtls linkerd linkerd-nomtls set-context

# Deployment steps must run in order (teardown before clean before install) even under `make -j`
# -- some shells alias make to `make -j<N>`, which otherwise runs teardown and clean at once.
.NOTPARALLEL:

# The playbooks run bare `kubectl` / kubernetes.core.k8s which use the workstation's
# CURRENT kubectl context. Pin it to the cluster first, otherwise a stray default
# (e.g. docker-desktop / microk8s) makes every kubectl call hit the wrong API server.
set-context:
	@echo "🎯 Using kube context: $(KUBECTX)"
	kubectl config use-context $(KUBECTX)

clean: set-context
	@echo "🧹 Triggering Deep Clean Playbook..."
	ansible-playbook ansible/00_deep_clean.yml -i $(INVENTORY)

teardown: set-context
	@echo "🧨 Triggering Teardown Playbook..."
	ansible-playbook ansible/01_teardown.yml -i $(INVENTORY)

baseline: set-context teardown clean
	@echo "🚀 Deploying Baseline via Ansible..."
	ansible-playbook ansible/phase_baseline.yml -i $(INVENTORY)

istio: set-context teardown clean
	@echo "🕸️ Deploying Istio via Ansible..."
	ansible-playbook ansible/phase_istio.yml -i $(INVENTORY)

# I-P configuration: full Istio deploy (same as `make istio`), then mTLS switched off with
# PeerAuthentication DISABLE. The Envoy sidecars stay in the data path; only encryption is
# removed. Istio pushes the policy over xDS, so no pod restart is needed.
istio-nomtls: istio
	@echo "🔓 Disabling mTLS in $(TEST_NS) (PeerAuthentication DISABLE)..."
	kubectl --context $(KUBECTX) apply -f $(ISTIO_PA)/peer-authentication-disable.yaml
	@echo "⏳ Waiting for $(TEST_NS) deployments to become Available..."
	kubectl --context $(KUBECTX) -n $(TEST_NS) wait --for=condition=Available deployment --all --timeout=300s
	@echo "✅ mTLS mode: $$(kubectl --context $(KUBECTX) -n $(TEST_NS) get peerauthentication default -o jsonpath='{.spec.mtls.mode}')"
	@echo "🚪 Gateway NodePort (pass to Phase A as -u http://<node>:PORT; it changes on every install): $$(kubectl --context $(KUBECTX) -n istio-system get svc istio-ingressgateway -o jsonpath='{.spec.ports[?(@.port==80)].nodePort}')"

linkerd: set-context teardown clean
	@echo "🕸️ Deploying Linkerd via Ansible..."
	ansible-playbook ansible/phase_linkerd.yml -i $(INVENTORY)

# L-P configuration. Linkerd has no mTLS switch, so this is NOT an encryption-off variant:
# every proxy stays injected, but the application ports (and the ingress controller's) are
# excluded from proxy interception via skip-inbound/outbound-ports. Report it as proxy bypass.
linkerd-nomtls: set-context teardown clean
	@echo "🕸️ Deploying Linkerd with application ports bypassing the proxy (L-P)..."
	ansible-playbook ansible/phase_linkerd.yml -i $(INVENTORY) -e linkerd_bypass=true
	@echo "⏳ Waiting for $(TEST_NS) deployments to become Available..."
	kubectl --context $(KUBECTX) -n $(TEST_NS) wait --for=condition=Available deployment --all --timeout=300s
	@echo "✅ Bypass annotations on $(TEST_NS): $$(kubectl --context $(KUBECTX) get ns $(TEST_NS) -o jsonpath='{.metadata.annotations}')"
	@echo "🚪 Ingress: http://<node>:30080 (static NodePort)"
