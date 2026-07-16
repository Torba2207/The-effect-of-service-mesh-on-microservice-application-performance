# SETUP GUIDE (From Zero)

This guide is for teammates to bootstrap the whole environment locally and run integration tests end-to-end.

Target result:
1. AI service runs on external VM (`10.29.20.120`) via Docker Compose.
2. Baseline microservices run in Kubernetes namespace `thesis-test`.
3. `permutation-service` in K8s can call external `ai-service`.

---

## 1) Access requirements

### VPN (mandatory)
- **Type:** `SSTP`
- **Address:** `pl5gvpn.kti.gda.pl`
- **Username:** `exp20`
- **Password:** check in Discord

### Infrastructure credentials
- **Hosts:** `10.29.20.X`, where `X = 101-103, 111-113, 120, 130`
- **SSH user:** `root`
- **SSH password:** check in Discord

---

## 2) Local prerequisites

Install:
- `git`
- `docker` + `docker compose`
- `kubectl`
- `ansible`
- `python3` + `pip` (or Windows Python)
- `ssh` (and `ssh-copy-id` for Linux shell flow)

Install Ansible K8s collection:

```bash
ansible-galaxy collection install kubernetes.core
```

---

## 3) Linux vs Windows workflow

### Linux (Ubuntu/Debian/Fedora etc.)
Use normal shell (`bash`) for all commands in this guide.

### Windows
Two supported options:
1. **WSL2 (recommended)** for the same flow as Linux (`*.sh` scripts).
2. **PowerShell** with native Windows scripts (`*.ps1`) included in this repository.

If using WSL2:
1. Install WSL2 + Ubuntu.
2. Install Docker Desktop and enable WSL integration.
3. Install `kubectl`, `ansible`, `ssh` inside WSL.
4. Run Linux commands from this guide inside WSL.

---

## 4) Clone repository

```bash
git clone git@github.com:Torba2207/The-effect-of-service-mesh-on-microservice-application-performance.git
cd The-effect-of-service-mesh-on-microservice-application-performance
```

PowerShell:

```powershell
git clone git@github.com:Torba2207/The-effect-of-service-mesh-on-microservice-application-performance.git
Set-Location .\The-effect-of-service-mesh-on-microservice-application-performance
```

---

## 5) Configure SSH keys for all nodes

Expected key path used by Ansible inventory:
- `<path_to_your_key>`

Run:

```bash
chmod +x scripts/linux/setup_keys.sh
./scripts/linux/setup_keys.sh
```

PowerShell:

```powershell
.\scripts\windows\setup_keys.ps1
```

Script behavior:
- creates key directory
- creates key pair if missing
- copies public key to all required hosts:
  - `10.29.20.101`
  - `10.29.20.102`
  - `10.29.20.103`
  - `10.29.20.111`
  - `10.29.20.112`
  - `10.29.20.113`
  - `10.29.20.120`
  - `10.29.20.130`

---

## 6) Verify inventory

File:
- `deployments/ansible/inventory.ini`

Validate:
- all IPs are current
- `ansible_user=root`
- `ansible_ssh_private_key_file=<path_to_your_key>`

---

## 7) Configure local kubectl access (kubeconfig)

Ansible drives the cluster over SSH (section 5), but to run `kubectl` from your own machine — and
for `make baseline|istio|linkerd` in `deployments/` to work — your workstation needs the cluster's
kubeconfig selected as the current context. One-time setup; requires the VPN (section 1) connected.

Fetch the admin kubeconfig from the first control-plane node and point it at that node's API server:

```bash
# 1. copy the admin config from node1
scp -i <path_to_your_key> \
  root@10.29.20.101:/etc/kubernetes/admin.conf /tmp/pg-admin.conf

# 2. ensure it targets node1's reachable API server (127.0.0.1 only works ON the node)
sed -i 's#server: https://127.0.0.1:6443#server: https://10.29.20.101:6443#' /tmp/pg-admin.conf
#    verify the server line now reads https://10.29.20.101:6443 :
grep 'server:' /tmp/pg-admin.conf

# 3. give the context a clear, stable name
#    (source context name is usually kubernetes-admin@cluster.local; if not, list it with:
#     KUBECONFIG=/tmp/pg-admin.conf kubectl config get-contexts)
KUBECONFIG=/tmp/pg-admin.conf kubectl config rename-context \
  kubernetes-admin@cluster.local projekt-badawchy-cluster
```

Then merge it into your default `~/.kube/config` (recommended), or keep it standalone:

```bash
# Option A — merge into ~/.kube/config (recommended)
KUBECONFIG=~/.kube/config:/tmp/pg-admin.conf kubectl config view --flatten > /tmp/merged.conf
mkdir -p ~/.kube && mv /tmp/merged.conf ~/.kube/config && chmod 600 ~/.kube/config

# Option B — standalone file (add the export to ~/.bashrc to persist)
mkdir -p ~/.kube && cp /tmp/pg-admin.conf ~/.kube/pg.conf
export KUBECONFIG=~/.kube/pg.conf
```

Select it as the current context and verify:

```bash
kubectl config use-context projekt-badawchy-cluster
kubectl get nodes            # all 6 nodes should report Ready
```

Notes:
- `10.29.20.101:6443` is only reachable through the **VPN** (section 1).
- The `make` targets in `deployments/` pin this context automatically
  (`kubectl config use-context projekt-badawchy-cluster` runs first), so a stray default context
  (e.g. `docker-desktop`, `microk8s`) cannot misdirect cluster operations. You can also switch to it
  manually at any time with the `use-context` command above.
- The kubeconfig grants full admin access to the cluster — keep `~/.kube/config` private
  (`chmod 600`) and do not commit it.

---

## 8) Configure GHCR access (for your own images)

Create GitHub PAT with:
- `read:packages`
- `write:packages`
- GHCR owner/username in image paths must be **lowercase** (GHCR repository naming requirement).

Login:

```bash
echo "<YOUR_PAT>" | docker login ghcr.io -u <YOUR_GITHUB_USERNAME> --password-stdin
```

PowerShell:

```powershell
"<YOUR_PAT>" | docker login ghcr.io -u <YOUR_GITHUB_USERNAME> --password-stdin
```

---

## 9) First-time bootstrap

```bash
chmod +x scripts/linux/*.sh
./scripts/linux/initial_setup.sh
```

PowerShell:

```powershell
.\scripts\windows\initial_setup.ps1
```

This runs:
- `deployments/ansible/setup_ai_vm.yml`
- `deployments/ansible/deploy_ai_vm.yml`
- `deployments/ansible/apply_baseline.yml`

---

## 10) Optional: build and push your own service images

Default tag in scripts is now generic: `team-test`.
Use a lowercase value for `GHCR_OWNER` when pushing packages.

```bash
GHCR_OWNER=<your_github_username> TAG=team-test ./scripts/linux/build_and_push.sh
```

PowerShell:

```powershell
.\scripts\windows\build_and_push.ps1 -GhcrOwner <your_github_username> -Tag team-test
```

---

## 11) Point K8s deployments to your images

```bash
GHCR_OWNER=<your_github_username> TAG=team-test NAMESPACE=thesis-test ./scripts/linux/point_to_new.sh
```

PowerShell:

```powershell
.\scripts\windows\point_to_new.ps1 -GhcrOwner <your_github_username> -Tag team-test -Namespace thesis-test
```

This also:
- applies `deployments/k8s/ai-service/ai-service-external.yaml`
- sets `AI_SERVICE_BASEURL=http://ai-service/` on permutation deployment

---

## 12) Re-run after changes

With build/push:

```bash
GHCR_OWNER=<your_github_username> TAG=team-test RUN_BUILD_PUSH=true ./scripts/linux/re_run.sh
```

PowerShell:

```powershell
.\scripts\windows\re_run.ps1 -RunBuildPush $true -GhcrOwner <your_github_username> -Tag team-test
```

Without build/push:

```bash
./scripts/linux/re_run.sh
```

PowerShell:

```powershell
.\scripts\windows\re_run.ps1
```

---

## Example (optional): end-to-end validation of permutation -> external AI

Check external AI mapping:

```bash
kubectl get svc,endpoints -n thesis-test ai-service
```

Port-forward permutation service:

```bash
kubectl port-forward -n thesis-test svc/permutation-service 10100:80
```

In second terminal:

```bash
curl -i -X POST http://localhost:10100/api/Permutation/generate-from-ai \
  -H "Content-Type: application/json" \
  -d '{"count":4,"minVal":1,"maxVal":10,"seed":42}'
```

Expected:
- HTTP `200 OK`
- valid permutations response

Optional logs:

```bash
kubectl logs -n thesis-test -l app=permutation-service --tail=200 --all-containers=true | \
  rg "Permutations requested from AI|Calling AI service|AI response"
```

---

## Troubleshooting (including firewall)

- **No connectivity to `10.29.20.X`:** check VPN status first.
- **SSH asks password every time:** rerun `./scripts/linux/setup_keys.sh` (or `.\scripts\windows\setup_keys.ps1`), then verify key path in inventory.
- **`docker push` denied:** verify GHCR PAT scopes and `docker login ghcr.io`.
- **`generate-from-ai` returns 404:** deployment uses old permutation image; rerun `point_to_new` script from `scripts/linux` or `scripts/windows`.
- **AI call fails from permutation:** reapply external service and restart permutation deployment:

```bash
kubectl apply -f deployments/k8s/ai-service/ai-service-external.yaml
kubectl set env deployment/permutation-service AI_SERVICE_BASEURL=http://ai-service/ -n thesis-test
kubectl rollout restart deployment/permutation-service -n thesis-test
```

Firewall checks:
- Local machine must allow outbound:
  - SSH `22/tcp` to `10.29.20.X`
  - Kubernetes API `6443/tcp` to control plane
- AI VM (`10.29.20.120`) must allow inbound:
  - `5005/tcp` (AI container port)
- If `kubectl port-forward` is blocked locally, allow loopback/local ports in host firewall.

Quick Linux checks:

```bash
sudo ufw status
sudo iptables -S
```

Windows checks:
1. Open **Windows Defender Firewall with Advanced Security**.
2. Confirm no outbound block rule for `10.29.20.0/24`.
3. Confirm no local rule blocking `kubectl` or local forwarded ports (e.g. `10100`).
