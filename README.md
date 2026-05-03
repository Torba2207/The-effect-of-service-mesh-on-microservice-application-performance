# 🚀 The Effect of Service Mesh on Microservice Application Performance

A **.NET 8 microservices sample** demonstrating an API Gateway (**YARP**) routing to multiple backend services.

This project is designed to run **with or without a service mesh** (e.g., Istio, Linkerd) to measure **performance differences** such as latency, CPU, and memory usage.

---

## 📋 Requirements

* [.NET 8 SDK](https://dotnet.microsoft.com/download/dotnet/8.0)
* Optional: `curl` or any HTTP client

### 🐧 Install on Linux (Ubuntu/Debian)

```bash
sudo apt update
sudo apt install dotnet-sdk-8.0 aspnetcore-runtime-8.0
```

### 🪟 Install on Windows

```bash
winget install Microsoft.DotNet.SDK.8
```

### ✅ Verify installation

```bash
dotnet --version
# Expected: 8.x.x
```

---

## 🏗️ Solution Structure

```
ServiceMeshStudy/
├── SharedModels/                  # DTOs shared across services
├── Gateway/                   # YARP reverse proxy (port 5000)
├── PermutationService/          # O(n!) permutations (port 5001)
├── FibonacciService/             # Fibonacci calculations (port 5002)
├── DifferentialEquationsService/ # ODE solver (port 5003)
├── IntegrationService/           # Numerical integration (port 5004)
├── AiService/                    # Test data generator (port 5005)
├── VideoService/                 # Video processing (port 5006)
├── DigitalFiltersService/        # Matrix filters (port 5007)
```

💡 All services are **independent Web APIs**, and the gateway routes incoming traffic.

---

## 🔌 Port Assignments

| Service                      | Port |
| ---------------------------- | ---- |
| ApiGateway                   | 5000 |
| PermutationsService          | 5001 |
| FibonacciService             | 5002 |
| DifferentialEquationsService | 5003 |
| IntegrationService           | 5004 |
| AiService                    | 5005 |
| VideoService                 | 5006 |
| DigitalFiltersService        | 5007 |

---

## ▶️ Running the Application

### 🧰 Option A — Visual Studio 2022

1. Open `ServiceMeshTestApplication.sln`
2. Set **Multiple Startup Projects**
3. Start:

   * `Gateway`
   * Desired backend services
4. Press **F5**

---

### 💻 Option B — Command Line

#### Build solution

```bash
dotnet build
```

#### Start Gateway

```bash
cd Gateway
dotnet run --urls "http://localhost:5000"
```

#### Start a service (example)

```bash
env DOTNET_SYSTEM_NET_DISABLEIPV6=1 dotnet run --project FibonacciService/FibonacciService.csproj
```

🪟 On Windows:

```cmd
set DOTNET_SYSTEM_NET_DISABLEIPV6=1 && dotnet run ...
```

---

### ⚡ Minimal Setup Example

```bash
# Gateway
cd Gateway && dotnet run --urls "http://localhost:5000"

# Integration Service
env DOTNET_SYSTEM_NET_DISABLEIPV6=1 dotnet run --project IntegrationService/IntegrationService.csproj

# Differential Service
env DOTNET_SYSTEM_NET_DISABLEIPV6=1 dotnet run --project DifferentialEquationsService/DifferentialEquationsService.csproj
```

---

### 🐳 Option C — Docker / Container Registry

Run the following commands from the `ServiceMeshTestApplication` directory:

```bash
# 1. Build and tag the image using lowercase
docker build -t ghcr.io/torba2207/permutation-service:latest -f PermutationService/Dockerfile .

# 2. Push the image to GHCR
docker push ghcr.io/torba2207/permutation-service:latest
```

---

## 🧪 Testing Endpoints

### 🔍 Health Checks

```bash
curl http://localhost:5000/Permutation/health
curl http://localhost:5000/Fibonacci/health
curl http://localhost:5000/Equations/health
curl http://localhost:5000/Integration/health
curl http://localhost:5000/Ai/health
curl http://localhost:5000/Video/health
curl http://localhost:5000/Filters/health
```

✅ Expected:

```json
{ "status": "healthy" }
```

---

### ➗ Integration Service

```bash
curl -X POST http://localhost:5000/api/integration/calculate -H "Content-Type: application/json" -d '{"function":"x^2","lowerBound":0,"upperBound":1,"steps":1000000}'
```

✔ Result: `0.333333...`

---

### 📈 Differential Equations

```bash
curl -X POST http://localhost:5000/api/equations/solve -H "Content-Type: application/json" -d '{"function":"x^2","initialConditionX":0,"initialConditionY":0,"range":2,"steps":5}'
```

---

### 🔢 Permutations

```bash
curl -X POST http://localhost:5000/api/permutation/generate -H "Content-Type: application/json" -d '{"set":[1,2,3]}'
```

---

### 🔁 Fibonacci (large input)

```bash
curl -X POST http://localhost:5000/api/fibonacci/calculate -H "Content-Type: application/json" -d '{"n": 10000}'
```

---

## 🛠️ Troubleshooting

### ❌ Port Already in Use

* Change port:

```bash
dotnet run --urls "http://localhost:5008"
```

* Update gateway config

---

### ⚠️ 502 / 503 Errors

* Service not running
* Port mismatch
* Check gateway logs (YARP debug enabled)

---

### 🌐 IPv6 Issues

```bash
DOTNET_SYSTEM_NET_DISABLEIPV6=1
```

---

### 📉 Unsupported Functions

Supported:

* `x^2`, `sin`, `cos`, `exp`, `1/x`

For advanced:

* `/evaluate`
* `/antiderivative`

---

## ⚙️ Configuration Notes

* **Routing**: `Gateway/appsettings.json`
* **Ports**: `launchSettings.json`
* **Shared DTOs**: `SharedModels`

