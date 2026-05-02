#set page(paper: "a4", margin: 1.25in)
#set text(font: "Linux Libertine", size: 11pt)
#set par(justify: true)

#align(center)[
  #text(20pt, weight: "bold")[Kubernetes HA Cluster Deployment]
  #v(0.5em)
  #text(14pt)[Kubespray Blueprint (3 Control Plane + 3 Data Plane)]
  #v(1em)
]

= Architecture Summary
This document details the configuration for a 6-node Highly Available Kubernetes cluster. 
- *Network Plugin (CNI):* Calico
- *SSH Authentication:* Custom identity key (`pgPB`)
- *Execution Environment:* Local Control Machine
- *Target User:* `root` directly (bypassing sudo escalation)

= Phase 1: Workspace Preparation
Ensure infrastructure code is kept separate from application code. We use the stable `v2.30.0` release of Kubespray. The Kubespray engine is cloned to a local tools directory, while our cluster inventory is stored in the project repository.
```bash
mkdir -p ~/Tools/k8s-infrastructure
cd ~/Tools/k8s-infrastructure

git clone [https://github.com/kubernetes-sigs/kubespray.git](https://github.com/kubernetes-sigs/kubespray.git)
cd kubespray

git fetch --tags
git checkout v2.30.0
```
= Phase 2: Python Environment Setup
Kubespray relies on specific versions of Ansible and Python packages. Create and activate a standard virtual environment to isolate these dependencies.
```bash
python3 -m venv venv
source venv/bin/activate
pip install -U pip
pip install -r requirements.txt
```
= Phase 3: SSH Key Distribution
The control machine must have passwordless SSH access to all 6 virtual machines as the root user. Distribute the custom public key to each node:
```bash
KEY="~/Documents/PG/Projects/.sshkeys/pgPB.pub"
ssh-copy-id -i $KEY root@10.29.20.101
ssh-copy-id -i $KEY root@10.29.20.102
ssh-copy-id -i $KEY root@10.29.20.103
ssh-copy-id -i $KEY root@10.29.20.111
ssh-copy-id -i $KEY root@10.29.20.112
ssh-copy-id -i $KEY root@10.29.20.113
```
#pagebreak()
= Phase 4: Cluster Configuration
Create a dedicated inventory space inside the version-controlled project repository based on the Kubespray sample.
```bash
REPO_DIR="~/Documents/PG/Projects/The-effect-of-service-mesh-on-microservice-application-performance"
mkdir -p $REPO_DIR/infrastructure/k8s
cp -rfp ~/Tools/k8s-infrastructure/kubespray/inventory/sample $REPO_DIR/infrastructure/k8s/mycluster
```
Manually define the precise cluster topology by editing the hosts.yaml file:
```bash
nano $REPO_DIR/infrastructure/k8s/mycluster/hosts.yaml
```
Replace the file contents with the following YAML structure. Nodes 1-3 act as the Highly Available Control Plane and etcd datastore. Nodes 4-6 act exclusively as Data Plane workers.
#pagebreak()
```yaml
all:
  hosts:
    node1:
      ansible_host: 10.29.20.101
      ip: 10.29.20.101
      access_ip: 10.29.20.101
    node2:
      ansible_host: 10.29.20.102
      ip: 10.29.20.102
      access_ip: 10.29.20.102
    node3:
      ansible_host: 10.29.20.103
      ip: 10.29.20.103
      access_ip: 10.29.20.103
    node4:
      ansible_host: 10.29.20.111
      ip: 10.29.20.111
      access_ip: 10.29.20.111
    node5:
      ansible_host: 10.29.20.112
      ip: 10.29.20.112
      access_ip: 10.29.20.112
    node6:
      ansible_host: 10.29.20.113
      ip: 10.29.20.113
      access_ip: 10.29.20.113
  children:
    kube_control_plane:
      hosts:
        node1:
        node2:
        node3:
    kube_node:
      hosts:
        node4:
        node5:
        node6:
    etcd:
      hosts:
        node1:
        node2:
        node3:
    k8s_cluster:
      children:
        kube_control_plane:
        kube_node:
    calico_rr:
      hosts: {}
```
= Phase 5: Cluster Execution
Execute the master Ansible playbook from within the Kubespray directory, but point it (-i) to the inventory file stored in the project repository.
```bash
cd ~/Tools/k8s-infrastructure/kubespray

ansible-playbook -i ~/Documents/PG/Projects/The-effect-of-service-mesh-on-microservice-application-performance/infrastructure/k8s/mycluster/hosts.yaml \
  -u root \
  --private-key=~/Documents/PG/Projects/.sshkeys/pgPB \
  cluster.yml
  ```
  = Phase 6: Verification
Once the Ansible deployment completes successfully, connect to the primary control plane node to verify the cluster state.
```bash
ssh -i ~/Documents/PG/Projects/.sshkeys/pgPB root@10.29.20.101
kubectl get nodes
```
All six nodes should report a Ready status, successfully confirming the deployment.