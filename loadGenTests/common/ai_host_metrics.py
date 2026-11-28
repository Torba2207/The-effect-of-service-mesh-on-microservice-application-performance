"""PromQL for the bare-metal AI host (ai_rtx), shared by collect_metrics.py and extract_timeseries.py.

Prometheus scrapes three exporters on the host every 10 s (deployments/ansible/monitoring_ai_host.yml,
deployments/k8s/monitoring/ai-host-scrapeconfig.yaml):

  job="ai-host-cadvisor"  per Docker container (label name=) and per systemd unit (label unit=)
  job="ai-host-node"      node_exporter: the whole host
  job="ai-host-gpu"       nvidia_smi_* of the RTX 4070

The host-side mesh proxies are systemd units (deployments/ansible/ai_mesh.yml), measured with the
same cAdvisor metrics as the sidecars in the pods:

  proxy  ("sidecar" columns)        istio: istio (pilot-agent + Envoy, as the istio-proxy container)
                                    consul: consul-envoy          linkerd: linkerd-proxy
  mesh infrastructure the pods do   consul: consul (client agent; the pods' consul-dataplane has none)
  not have (_ai_host_meshinfra)     linkerd: spire-server, spire-agent (identity for the host proxy)

With the AI host outside the mesh (AI_MESH=0) these units do not run: the queries return nothing and
the columns stay empty. In L-P the host proxy runs but is bypassed, as the pods' proxies are.
"""

CADVISOR = 'job="ai-host-cadvisor"'
NODE = 'job="ai-host-node"'
GPU = 'job="ai-host-gpu"'

# The AI service: the nginx load balancer and its GPU backends (compose project on the host).
APP = CADVISOR + ',name=~"ai-load-balancer|ai-service-[0-9]+"'

PROXY_UNITS = {"istio": "istio", "consul": "consul-envoy", "linkerd": "linkerd-proxy"}
INFRA_UNITS = {"consul": "consul", "linkerd": "spire-server|spire-agent"}

UP = 'max(up{%s})' % CADVISOR


def groups(mesh):
    """[(csv service, role, cAdvisor selector)] for one mesh. role: app | sidecar."""
    out = [("_ai_host", "app", APP)]
    if mesh in PROXY_UNITS:
        out.append(("_ai_host", "sidecar", CADVISOR + ',unit=~"%s"' % PROXY_UNITS[mesh]))
    if mesh in INFRA_UNITS:
        out.append(("_ai_host_meshinfra", "app", CADVISOR + ',unit=~"%s"' % INFRA_UNITS[mesh]))
    return out


def cpu_expr(selector, window):
    """CPU in cores."""
    return 'sum(rate(container_cpu_usage_seconds_total{%s}[%s]))' % (selector, window)


def mem_expr(selector):
    """Working set in MiB."""
    return 'sum(container_memory_working_set_bytes{%s})/1048576' % selector


def node_cpu_expr(window):
    """Whole host, busy CPU in cores (all modes but idle, iowait and steal)."""
    return 'sum(rate(node_cpu_seconds_total{%s,mode!~"idle|iowait|steal"}[%s]))' % (NODE, window)


def node_mem_expr():
    """Whole host, memory in use in MiB (MemTotal - MemAvailable)."""
    return '(sum(node_memory_MemTotal_bytes{%s}) - sum(node_memory_MemAvailable_bytes{%s}))/1048576' % (NODE, NODE)


def gpu_util_expr():
    """GPU utilisation in percent (average over the host's GPUs)."""
    return 'avg(nvidia_smi_utilization_gpu_ratio{%s})*100' % GPU
