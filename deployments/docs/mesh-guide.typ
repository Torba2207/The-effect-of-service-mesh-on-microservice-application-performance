#set page(
  paper: "a4",
  margin: (x: 2cm, y: 2cm),
)
#set text(
  font: "Linux Libertine",
  size: 11pt,
)

#set par(justify: true)

#align(center)[
  #text(size: 20pt, weight: "bold")[Microservice Containerization & Service Mesh Guide]
  #v(1em)
  #text(size: 14pt)[Istio and Linkerd on Bare-Metal Kubernetes]
  #v(2em)
]

= Containerizing Services & Pushing to GHCR

Before a service can be deployed to Kubernetes or injected with a service mesh proxy, it must be packaged into a container image and hosted in a registry.

== 1. Build the Container Image
Navigate to your microservice's source code directory (where your `Dockerfile` is located) and build the image. Tag it appropriately for the GitHub Container Registry (GHCR).
```bash
docker build -t ghcr.io/<your-github-username>/permutation-service:latest .
```
== 2. Authenticate with GHCR
Create a Personal Access Token (Classic) in GitHub with the read:packages and write:packages scopes. Use this token to log in via the Docker CLI.
```bash
echo $CR_PAT | docker login ghcr.io -u <your-github-username> --password-stdin
```
== 3. Push the Image
Push your newly built image to the registry so your Kubernetes cluster can pull it.
```bash
docker push ghcr.io/<your-github-username>/permutation-service:latest
```
#v(1em)
= Kubernetes Deployments & Services

To run your containerized application, you need standard Kubernetes resources.

- Deployment: Manages the replica pods and tells Kubernetes which container image to pull.

- Service: Provides stable internal networking (ClusterIP) or external access (NodePort).

Example Baseline Architecture:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: permutation-service
spec:
  replicas: 5
  selector:
    matchLabels:
      app: permutation-service
  template:
    metadata:
      labels:
        app: permutation-service
    spec:
      containers:
      - name: permutation-service
        image: ghcr.io/<your-github-username>/permutation-service:latest
        ports:
        - containerPort: 5001
---
apiVersion: v1
kind: Service
metadata:
  name: permutation-service
spec:
  type: NodePort # Use ClusterIP if exposing via Istio Gateway
  selector:
    app: permutation-service
  ports:
    - port: 80
      targetPort: 5001
      nodePort: 30000
```
#v(1em)
= Setting up Istio (Envoy Proxy)

Istio utilizes the Envoy proxy at Layer 7 to manage traffic. It requires a shared Gateway and individual VirtualServices for routing.

== 1. Installation & PATH Setup
Download the Istio CLI into a dedicated tools directory and add it to your system PATH.
```bash
curl -L [https://istio.io/downloadIstio](https://istio.io/downloadIstio) | ISTIO_VERSION=1.21.0 sh -
mv istio-1.21.0/bin/istioctl ~/Tools/istioctl
fish_add_path ~/Tools # If using Fish shell
```
== 2. Install the Control Plane
Install the default profile, which provides the core istiod control plane and the Ingress Gateway without heavy observability overhead.
```bash
istioctl install --set profile=default -y
```
== 3. Namespace Injection
Create an isolated namespace and label it. Istio will automatically inject Envoy sidecars into any pods deployed here.
```bash
kubectl create namespace istio-test
kubectl label namespace istio-test istio-injection=enabled
```
== 4. Routing: Gateway and VirtualService
Istio requires a Gateway (the shared front door) and a VirtualService (the routing logic based on HTTP paths).
```yaml
# The Shared Gateway
apiVersion: networking.istio.io/v1beta1
kind: Gateway
metadata:
  name: main-gateway
  namespace: istio-test
spec:
  selector:
    istio: ingressgateway
  servers:
  - port:
      number: 80
      name: http
      protocol: HTTP
    hosts:
    - "*"
---
# The Service-Specific Route
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: permutation-vs
  namespace: istio-test
spec:
  hosts:
  - "*"
  gateways:
  - main-gateway
  http:
  - match:
    - uri:
        prefix: /api/permutation
    route:
    - destination:
        host: permutation-service.istio-test.svc.cluster.local
        port:
          number: 80
```
#v(1em)
= Setting up Linkerd (Rust Micro-Proxy)

Linkerd is designed to be highly lightweight, utilizing a custom Rust micro-proxy. It relies on standard Kubernetes routing (like NodePorts or existing Ingress controllers) rather than deploying its own Gateway pods.

== 1. Installation & PATH Setup
Install the Linkerd CLI to your tools directory.
```bash
curl --proto '=https' --tlsv1.2 -sSfL [https://run.linkerd.io/install](https://run.linkerd.io/install) | \
  INSTALLROOT=$HOME/Tools/linkerd sh
fish_add_path ~/Tools/linkerd/bin
```
== 2. Pre-requisites (Gateway API)
Modern Linkerd requires the Kubernetes Gateway API CRDs to be present in the cluster before installation.
```bash
kubectl apply --server-side -f \
  [https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.1/standard-install.yaml](https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.1/standard-install.yaml)
```
== 3. Install the Control Plane
Install the Linkerd CRDs first, followed by the core control plane.
```bash
linkerd install --crds | kubectl apply -f -
linkerd install | kubectl apply -f -
linkerd check # Wait for validation
```
== 4. Namespace Injection
Unlike Istio's labels, Linkerd uses annotations to trigger sidecar proxy injection.
```bash
kubectl create namespace linkerd-test
kubectl annotate namespace linkerd-test linkerd.io/inject=enabled
```
Deploy your standard Kubernetes Deployment and Service (e.g., using a NodePort) into the linkerd-test namespace, and the Rust proxy will automatically intercept the traffic.
