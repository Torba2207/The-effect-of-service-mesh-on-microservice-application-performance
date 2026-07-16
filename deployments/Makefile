# --- VARIABLES ---
INVENTORY = ansible/inventory.ini
KUBECTX   = projekt-badawchy-cluster

.PHONY: clean teardown baseline istio linkerd set-context

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

linkerd: set-context teardown clean
	@echo "🕸️ Deploying Linkerd via Ansible..."
	ansible-playbook ansible/phase_linkerd.yml -i $(INVENTORY)