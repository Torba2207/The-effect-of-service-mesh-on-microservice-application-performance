# --- VARIABLES ---
SSH_KEY=~/Documents/PG/Projects/.sshkeys/pgPB
TEST_NS=thesis-test
APP_DIR=k8s/permutation-service
ISTIO_DIR=istio

# Cluster IPs for SSH connections
NODE1_IP=10.29.20.101
NODE4_IP=10.29.20.111
NODE5_IP=10.29.20.112
NODE6_IP=10.29.20.113
WORKER_IPS=$(NODE4_IP) $(NODE5_IP) $(NODE6_IP)

.PHONY: clean-nodes teardown monitor baseline istio linkerd

# 1. THE DEEP CLEAN (11GB Disk Survival)
clean-nodes:
	@echo "🧹 Deep cleaning worker nodes via explicit SSH key..."
	@for ip in $(WORKER_IPS); do \
		echo "Connecting to $$ip..."; \
		ssh -i $(SSH_KEY) root@$$ip "crictl rmi --prune && find /var/log/pods -type f -name '*.log' -exec truncate -s 0 {} +"; \
	done
	@echo "✅ Nodes cleaned and ready."

# 2. THE TOTAL RESET
teardown:
	@echo "🧨 Tearing down all apps and meshes..."
	-kubectl delete namespace $(TEST_NS) --ignore-not-found
	-ssh -i $(SSH_KEY) root@$(NODE1_IP) "helm uninstall cluster-monitor -n monitoring --ignore-not-found"
	-kubectl delete namespace monitoring --ignore-not-found
	-istioctl uninstall --purge -y
	-kubectl delete namespace istio-system --ignore-not-found
	-linkerd uninstall | kubectl delete -f -
	@echo "✅ Cluster reset to Zero State."

# 3. PROMETHEUS-LITE (Memory-based monitoring piped to node1)
monitor:
	@echo "📊 Installing Prometheus-Lite (RAM-only) via SSH pipe..."
	cat lite-values.yaml | ssh -i $(SSH_KEY) root@$(NODE1_IP) "cat > /tmp/lite-values.yaml && helm install cluster-monitor prometheus-community/kube-prometheus-stack -n monitoring --create-namespace -f /tmp/lite-values.yaml"
	@echo "⏳ Waiting for monitoring stack to initialize..."
	sleep 20

# 3.1. Metrics Server (for k6 to pull resource metrics)
metrics:
	@echo "📊 Installing Metrics Server..."
	kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
	kubectl patch deployment metrics-server -n kube-system --type 'json' -p '[{"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--kubelet-insecure-tls"}]'
	@echo "⏳ Waiting 15 seconds for Metrics Server to initialize..."
	sleep 15

# 4. PHASE 1: BASELINE (No Mesh)
baseline: teardown clean-nodes metrics
	@echo "🚀 Deploying Baseline Environment..."
	kubectl create namespace $(TEST_NS)
	kubectl apply -f $(APP_DIR)/permutation-service-latest.yaml -n $(TEST_NS)
	kubectl apply -f $(APP_DIR)/permutation-service-service.yaml -n $(TEST_NS)
	kubectl rollout status deployment/permutation-service -n $(TEST_NS)
	@echo "🎯 Baseline Ready. You can now run your k6 script."

# 5. PHASE 2: ISTIO
istio: teardown clean-nodes metrics
	@echo "🕸️ Installing Istio Control Plane..."
	istioctl install --set profile=default -y
	kubectl create namespace $(TEST_NS)
	kubectl label namespace $(TEST_NS) istio-injection=enabled
	@echo "🚀 Deploying app with Istio configs..."
	kubectl apply -f $(APP_DIR)/permutation-service-istio-latest.yaml -n $(TEST_NS)
	kubectl apply -f $(APP_DIR)/permutation-service-istio-service.yaml -n $(TEST_NS)
	kubectl apply -f $(ISTIO_DIR)/istio-main-gateway.yaml -n $(TEST_NS)
	kubectl apply -f $(APP_DIR)/permutation-virtual-service-istio.yaml -n $(TEST_NS)
	kubectl rollout status deployment/permutation-service -n $(TEST_NS)
	@echo "🎯 Istio Environment Ready. You can now run your k6 script."

# 6. PHASE 3: LINKERD
linkerd: teardown clean-nodes metrics
	@echo "🕸️ Installing Linkerd Control Plane..."
	linkerd install --crds | kubectl apply -f -
	linkerd install | kubectl apply -f -
	linkerd check
	kubectl create namespace $(TEST_NS)
	kubectl annotate namespace $(TEST_NS) linkerd.io/inject=enabled
	@echo "🚀 Deploying app with Linkerd configs..."
	kubectl apply -f $(APP_DIR)/permutation-service-linkerd-latest.yaml -n $(TEST_NS)
	kubectl apply -f $(APP_DIR)/permutation-service-linkerd-service.yaml -n $(TEST_NS)
	kubectl rollout status deployment/permutation-service -n $(TEST_NS)
	@echo "🎯 Linkerd Environment Ready. You can now run your k6 script."