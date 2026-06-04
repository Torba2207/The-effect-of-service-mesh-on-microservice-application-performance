# --- VARIABLES ---
INVENTORY = ansible/inventory.ini

.PHONY: clean teardown baseline istio linkerd

clean:
	@echo "🧹 Triggering Deep Clean Playbook..."
	ansible-playbook ansible/00_deep_clean.yml -i $(INVENTORY)

teardown:
	@echo "🧨 Triggering Teardown Playbook..."
	ansible-playbook ansible/01_teardown.yml -i $(INVENTORY)

baseline: teardown clean
	@echo "🚀 Deploying Baseline via Ansible..."
	ansible-playbook ansible/phase_baseline.yml -i $(INVENTORY)

istio: teardown clean
	@echo "🕸️ Deploying Istio via Ansible..."
	ansible-playbook ansible/phase_istio.yml -i $(INVENTORY)

linkerd: teardown clean
	@echo "🕸️ Deploying Linkerd via Ansible..."
	ansible-playbook ansible/phase_linkerd.yml -i $(INVENTORY)