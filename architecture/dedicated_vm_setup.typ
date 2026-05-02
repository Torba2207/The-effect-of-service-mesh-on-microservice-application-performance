#set page(paper: "a4", margin: 1.25in)
#set text(font: "Linux Libertine", size: 11pt)
#set par(justify: true)

#align(center)[
  #text(20pt, weight: "bold")[Standalone AI Node Deployment]
  #v(0.5em)
  #text(14pt)[Ansible Blueprint (Docker Container Engine)]
  #v(1em)
]

= Architecture Summary
This document details the configuration for a dedicated, standalone AI virtual machine. 
- *Runtime Environment:* Docker Engine & Docker Compose (CPU-only)
- *SSH Authentication:* Custom identity key (`pgPB`)
- *Execution Environment:* Local Control Machine (via existing Python `venv`)
- *Target User:* `root` directly (bypassing sudo escalation)

= Phase 1: Workspace Preparation
Create a dedicated directory for the AI infrastructure, keeping it strictly separate from the Kubernetes codebase.

```bash
mkdir -p ~/Tools/ai-infrastructure
cd ~/Tools/ai-infrastructure
```

= Phase 2: Inventory Configuration
Create an Ansible inventory file to define the AI node's IP address.
```bash
nano hosts.yaml
```

Add the following configuration, replacing the IP address if the infrastructure changes:
```yaml
all:
  hosts:
    ai_node:
      ansible_host: 10.29.20.120
```

= Phase 3: Playbook Creation
Create the main Ansible playbook to systematically install prerequisites, configure the official Docker APT repository, and install the Docker engine.
```bash
nano setup-ai.yaml
```
Insert the following YAML definition:
```yaml
---
- name: Provision Standalone AI Node
  hosts: ai_node
  become: yes
  
  tasks:
    - name: Update apt cache and install prerequisites
      apt:
        pkg:
          - apt-transport-https
          - ca-certificates
          - curl
          - software-properties-common
          - gnupg
        state: present
        update_cache: yes

    - name: Create directory for Docker keyrings
      file:
        path: /etc/apt/keyrings
        state: directory
        mode: '0755'

    - name: Add Docker official GPG key
      shell: |
        curl -fsSL [https://download.docker.com/linux/ubuntu/gpg](https://download.docker.com/linux/ubuntu/gpg) | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        chmod a+r /etc/apt/keyrings/docker.gpg
      args:
        creates: /etc/apt/keyrings/docker.gpg

    - name: Add Docker APT repository
      shell: |
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] [https://download.docker.com/linux/ubuntu](https://download.docker.com/linux/ubuntu) $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
      args:
        creates: /etc/apt/sources.list.d/docker.list

    - name: Install Docker Engine and Docker Compose
      apt:
        pkg:
          - docker-ce
          - docker-ce-cli
          - containerd.io
          - docker-compose-plugin
        state: latest
        update_cache: yes

    - name: Ensure Docker service is running and enabled on boot
      service:
        name: docker
        state: started
        enabled: yes
```
= Phase 4: Execution
Activate the Python virtual environment containing Ansible (from the prior Kubernetes setup), then execute the playbook logging in directly as root.
```bash
source ~/Tools/k8s-infrastructure/kubespray/venv/bin/activate

ansible-playbook -i hosts.yaml \
  -u root \
  --private-key=~/Documents/PG/Projects/.sshkeys/pgPB \
  setup-ai.yaml
```
= Phase 5: Verification
Connect to the AI node to verify the Docker installation is healthy, properly communicating with systemd, and capable of pulling images from the internet.
```bash
ssh -i ~/Documents/PG/Projects/.sshkeys/pgPB root@10.29.20.200

systemctl status docker
docker compose version
docker run hello-world
```
The output should display Docker as active (running) and successfully print the "Hello from Docker!" test message.
