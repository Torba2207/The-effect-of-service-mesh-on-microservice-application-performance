# --- VARIABLES ---
INVENTORY = ansible/inventory.ini
KUBECTX   = projekt-badawchy-cluster
TEST_NS   = thesis-test
ISTIO_PA  = k8s/istio

# AI_MESH=1 joins the bare-metal AI host to the mesh of the target (ansible/ai_mesh.yml): the
# AI service becomes a mesh member (own proxy, mTLS on the last hop) instead of an external
# dependency. Default 0 = the AI host stays outside the mesh, as in all earlier measurements.
# `make teardown` (and so every deploy target) always removes mesh components from the host.
AI_MESH ?= 0
AI_MESH_PLAY = ansible-playbook ansible/ai_mesh.yml -i $(INVENTORY)
AI_STATE = echo "AI host: $$(kubectl --context $(KUBECTX) -n $(TEST_NS) get svc ai-service -o jsonpath='{.spec.selector.app}' 2>/dev/null | grep -q . && echo 'IN the mesh (AI_MESH=1)' || echo 'external dependency (AI_MESH=0)')"

ifeq ($(AI_MESH),1)
ifneq ($(filter baseline linkerd linkerd-nomtls consul,$(MAKECMDGOALS)),)
$(error AI_MESH=1 is implemented for the Istio targets only so far (istio, istio-mtls, istio-nomtls); baseline has no mesh)
endif
endif

.PHONY: clean teardown baseline istio istio-mtls istio-nomtls linkerd linkerd-nomtls consul set-context lg-bootstrap ai-bgp ai-bgp-nonat ai-monitoring

# Deployment steps must run in order (teardown before clean before install) even under `make -j`
# -- some shells alias make to `make -j<N>`, which otherwise runs teardown and clean at once.
.NOTPARALLEL:

# The playbooks run bare `kubectl` / kubernetes.core.k8s which use the workstation's
# CURRENT kubectl context. Pin it to the cluster first, otherwise a stray default
# (e.g. docker-desktop / microk8s) makes every kubectl call hit the wrong API server.
set-context:
	@echo "Using kube context: $(KUBECTX)"
	kubectl config use-context $(KUBECTX)

clean: set-context
	@echo "Triggering Deep Clean Playbook..."
	ansible-playbook ansible/00_deep_clean.yml -i $(INVENTORY)

teardown: set-context
	@echo "Triggering Teardown Playbook..."
	ansible-playbook ansible/01_teardown.yml -i $(INVENTORY)
	@echo "Removing mesh components from the AI host (if any)..."
	$(AI_MESH_PLAY) -e ai_mesh_state=absent

baseline: set-context teardown clean
	@echo "Deploying Baseline via Ansible..."
	ansible-playbook ansible/phase_baseline.yml -i $(INVENTORY)

istio: set-context teardown clean
	@echo "Deploying Istio via Ansible..."
	ansible-playbook ansible/phase_istio.yml -i $(INVENTORY)
	@if [ "$(AI_MESH)" = 1 ]; then echo "Joining the AI host to the Istio mesh..."; $(AI_MESH_PLAY) -e ai_mesh_state=present -e ai_mesh=istio; fi

# I-S configuration: full Istio deploy (same as `make istio`), then mTLS forced on with
# PeerAuthentication STRICT. `make istio` alone leaves Istio PERMISSIVE, which is not a measured
# configuration.
istio-mtls: istio
	@echo "Enforcing mTLS in $(TEST_NS) (PeerAuthentication STRICT)..."
	kubectl --context $(KUBECTX) apply -f $(ISTIO_PA)/peer-authentication-strict.yaml
	@echo "Waiting for $(TEST_NS) deployments to become Available..."
	kubectl --context $(KUBECTX) -n $(TEST_NS) wait --for=condition=Available deployment --all --timeout=300s
	@if [ "$(AI_MESH)" = 1 ]; then echo "Checking the AI host's last hop (expect mutual_tls)..."; $(AI_MESH_PLAY) -e ai_mesh_state=present -e ai_mesh=istio -e ai_mesh_expect=mutual_tls --tags verify; fi
	@echo "mTLS mode: $$(kubectl --context $(KUBECTX) -n $(TEST_NS) get peerauthentication default -o jsonpath='{.spec.mtls.mode}')"
	@$(AI_STATE)
	@echo "Gateway NodePort (pass to Phase A as -u http://<node>:PORT; it changes on every install): $$(kubectl --context $(KUBECTX) -n istio-system get svc istio-ingressgateway -o jsonpath='{.spec.ports[?(@.port==80)].nodePort}')"

# I-P configuration: full Istio deploy (same as `make istio`), then mTLS switched off with
# PeerAuthentication DISABLE. The Envoy sidecars stay in the data path; only encryption is
# removed. Istio pushes the policy over xDS, so no pod restart is needed.
istio-nomtls: istio
	@echo "Disabling mTLS in $(TEST_NS) (PeerAuthentication DISABLE)..."
	kubectl --context $(KUBECTX) apply -f $(ISTIO_PA)/peer-authentication-disable.yaml
	@echo "Waiting for $(TEST_NS) deployments to become Available..."
	kubectl --context $(KUBECTX) -n $(TEST_NS) wait --for=condition=Available deployment --all --timeout=300s
	@if [ "$(AI_MESH)" = 1 ]; then echo "Checking the AI host's last hop (expect none)..."; $(AI_MESH_PLAY) -e ai_mesh_state=present -e ai_mesh=istio -e ai_mesh_expect=none --tags verify; fi
	@echo "mTLS mode: $$(kubectl --context $(KUBECTX) -n $(TEST_NS) get peerauthentication default -o jsonpath='{.spec.mtls.mode}')"
	@$(AI_STATE)
	@echo "Gateway NodePort (pass to Phase A as -u http://<node>:PORT; it changes on every install): $$(kubectl --context $(KUBECTX) -n istio-system get svc istio-ingressgateway -o jsonpath='{.spec.ports[?(@.port==80)].nodePort}')"

linkerd: set-context teardown clean
	@echo "Deploying Linkerd via Ansible..."
	ansible-playbook ansible/phase_linkerd.yml -i $(INVENTORY)

# L-P configuration. Linkerd has no mTLS switch, so this is NOT an encryption-off variant:
# every proxy stays injected, but the application ports (and the ingress controller's) are
# excluded from proxy interception via skip-inbound/outbound-ports. Report it as proxy bypass.
linkerd-nomtls: set-context teardown clean
	@echo "Deploying Linkerd with application ports bypassing the proxy (L-P)..."
	ansible-playbook ansible/phase_linkerd.yml -i $(INVENTORY) -e linkerd_bypass=true
	@echo "Waiting for $(TEST_NS) deployments to become Available..."
	kubectl --context $(KUBECTX) -n $(TEST_NS) wait --for=condition=Available deployment --all --timeout=300s
	@echo "Bypass annotations on $(TEST_NS): $$(kubectl --context $(KUBECTX) get ns $(TEST_NS) -o jsonpath='{.metadata.annotations}')"
	@echo "Ingress: http://<node>:30080 (static NodePort)"

# C-S configuration: Consul service mesh via Helm, no ACLs, Consul API Gateway as ingress.
# mTLS is always on in Consul. Needs helm; the playbook installs a storage provisioner.
# The playbook prints the gateway NodePort, which is dynamic like Istio's: pass it with -u.
# PROVISIONAL - to be reviewed with the thesis supervisor (docs/test-scenario.typ).
consul: set-context teardown clean
	@echo "Deploying Consul via Ansible (Helm)..."
	ansible-playbook ansible/phase_consul.yml -i $(INVENTORY)

# Prepare the load generator (lg) as a campaign host: kubectl, helm, istioctl, linkerd and
# ansible at the workstation's versions, the kubeconfig, an SSH key for the cluster nodes, a
# clone of the repository in /root/thesis. Run from the workstation.
lg-bootstrap:
	@echo "Bootstrapping the load generator..."
	ansible-playbook ansible/lg_bootstrap.yml -i $(INVENTORY)

# Flat network: the AI host becomes a BGP neighbour of Calico (FRR on the host + a global
# BGPPeer), so it has routes to every pod block. Independent of the mesh phase; re-run after
# adding or replacing nodes. ai-bgp-nonat additionally stops NATing pod -> AI traffic.
ai-bgp:
	@echo "Peering the AI host with Calico over BGP..."
	ansible-playbook ansible/network_ai_bgp.yml -i $(INVENTORY) -l 'control_plane,ai_bgp_host'

ai-bgp-nonat:
	@echo "Peering the AI host with Calico over BGP, no NAT for pod -> AI..."
	ansible-playbook ansible/network_ai_bgp.yml -i $(INVENTORY) -l 'control_plane,ai_bgp_host' -e ai_no_nat=true

# Metrics exporters on the AI host (cAdvisor incl. systemd units, node_exporter, GPU exporter),
# for measuring the mesh cost on the host. The Prometheus side is configured separately.
ai-monitoring:
	@echo "Deploying metrics exporters on the AI host..."
	ansible-playbook ansible/monitoring_ai_host.yml -i $(INVENTORY)
