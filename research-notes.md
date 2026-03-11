# Service Mesh Fundamentals: Providing Security, Reliability, and Observability to Kubernetes Applications

- Examples of existing solutions:
  - Istio
  - Linkerd
  - Consul
  - Kuma

# Mastering Service Mesh

### Authors: Anjali Khatri, Vikram Khatri

### Service Mesh definition by William Morgan in 2017

<i>A service mesh is a dedicated infrastructure layer for handling service-to-service communication. It's responsible for the reliable delivery of requests through the complex topology of services that comprise a modern, cloud-native application. In practice, the service mesh's implementation is an array of lightweight network proxies deployed alongside microservices, without the applications needing to be aware. </i><br>

The service mesh could secure communication between the microservices with TLS. The benefit here is that each developer no longer has to implement TLS encryption and decryption that's specific to the language they are writing in.<br>

The service mesh concept is a significant shift from earlier versions of DevOps, where operations were limited to software release management.<br>

Smart endpoints: Service-to-service communication is done through the intelligent endpoints, which is a DNS record that resolves to a microservice. The use of DNS records facilitates one service to communicate with others, and this eliminates the load balancer between microservices.

<i>Dumb pipes: Service-to-service communication uses basic network traffic protocols such as HTTP, REST, gRPC, and so on. This type of connection is opposed to a centralized smart pipe using the ESB/MQ of monolithic applications.</I><br> Martin Fowler, in his 2014 blog article<br>

### Service Mesh def. by Christian Posta

<i>Service mesh is a decentralized application networking infrastructure between your services. This decoupling provides resiliency, security, observability, and routing control.</i>

In a cloud-native environment, the service mesh has moved from Dev to Ops, and this is a significant shift because it lets the developers focus on their specialty<br>

Site Reliability Engineering (SRE)<br>

In the context of Kubernetes:<br>
- Basic service mesh:<br>
    - K8s provides basic service mesh "out of the box"
    - provides a round-robin balancing for requests to the target pods
    - dynamic function that manages iptables under the cover on each host (this process is transparent)
    - Pod is ready - the endpoints of the service are enabled to provide a connection from outside to the IP addresses of the pods.

- Advanced service mesh:
    - Istio, Linkerd, Consul, and so on can harness some advanced capabilities such as retry logic, timeouts, fallback, circuit breaking, and distributed tracing from it.

### Emerging trends
- We can extend the same service mesh control plane to multiple Kubernetes clusters, provided that each cluster has its own distinct IP address range.
- We can bring VMs, bare-metal, or other monolithic applications into the service mesh for traffic management and telemetry.
- We can have multiple Kubernetes clusters, with each having their control plane replicating the state of each group.
- We can have a federated service mesh, where each cluster runs its own control and data plane.


### Service Mesh rules:
- Observability: The control plane provides the observability of services running in the data plane.
- Routing: The routing rules for traffic management can be defined either graphically or through the use of configuration files and then pushed down from the control plane to all the data planes.
- Automatic scaling: The control plane services automatically scale to handle the increased workload.
- Separation of duties: The control plane UI allows operations to manage the service mesh independent of the development team.
- Trust: It pushes down secure communication protocols to the data planes and provides automatic renewal and management of certificates.
- Automatic service registration and discovery: The control plane integrates with the Kubernetes API server and discovers the service automatically as it's registered through application deployment procedures.
- Resilient: Pushes resiliency rules to all of the data planes. This acts as a sidecar proxy for traffic management.
