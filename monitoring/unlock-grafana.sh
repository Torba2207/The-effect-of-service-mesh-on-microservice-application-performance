#!/bin/bash

kubectl port-forward svc/cluster-monitor-grafana -n monitoring --address 0.0.0.0 3000:80
# This script forwards the Grafana service to localhost:3000, allowing you to access the Grafana dashboard from your browser at http://localhost:3000.