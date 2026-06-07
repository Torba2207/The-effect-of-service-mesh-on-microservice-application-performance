# 🚀 The Effect of Service Mesh on Microservice Application Performance

A **.NET 8 microservices sample** demonstrating an API Gateway (**YARP**) routing to multiple backend services.

This project is designed to run **with or without a service mesh** (e.g., Istio, Linkerd) to measure **performance differences** such as latency, CPU, and memory usage.

## ⚡ Quick Start for Teammates

For full environment bootstrap (VPN, Linux/Windows scripts, GHCR, Ansible/Kubernetes flow), use:

**[`docs/SETUP_GUIDE.md`](docs/SETUP_GUIDE.md)**

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
├── Gateway/                       # YARP reverse proxy (port 5000)
├── PermutationService/            # O(n!) permutation calculations (port 5001)
├── FibonacciService/              # Fibonacci sequence calculations (port 5002)
├── DifferentialEquationsService/  # ODE numerical solver (port 5003)
├── IntegrationService/            # Numerical integration solver (port 5004)
├── AiService/                     # AI-based data generation (port 5005)
├── VideoService/                  # Video compression & processing (port 5006)
├── DigitalFiltersService/         # Image filtering & convolution (port 5007)
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

### Locatig the Istio Gateway

```bash
kubectl get svc istio-ingressgateway -n istio-system
```

### k8s cluster shell
```bash
kubectl run curl-test --image=curlimages/curl -i --tty --rm -n thesis-test -- sh
```

### Check AI Service being k8s cluster shell
```bash
curl http://ai-service/api/Ai/health

curl -i -X POST http://ai-service/api/Ai/generate -H "Content-Type: application/json" -d '{"user_input": "Give me 10 random numbers between 1 and 100 with seed 42"}'
```

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

✅ Expected Response:

```json
{ "status": "healthy" }
```

---

### ➗ Integration Service

Calculate the integral of a function using numerical integration:

```bash
curl -X POST http://localhost:5000/api/integration/calculate \
  -H "Content-Type: application/json" \
  -d '{"function":"x^2","lowerBound":0,"upperBound":1,"steps":1000000}'
```

✅ Expected Response (Approximate Result: 0.333):

```json
{
  "success": true,
  "message": "Integral calculated successfully",
  "data": {
    "function": "x^2",
    "lowerBound": 0,
    "upperBound": 1,
    "steps": 1000000,
    "result": 0.3333333333332426
  },
  "executionTimeMs": 83,
  "cpuUsagePercent": 60.24,
  "memoryUsageMb": 0,
  "serviceName": "IntegrationService",
  "timestamp": "2026-06-03T21:05:33.4852247Z"
}
```

Calculate the antiderivative of a function:

```bash
curl -X POST http://localhost:5000/api/integration/antiderivative \
  -H "Content-Type: application/json" \
  -d '{"Expression":"x^2"}'
```

✅ Expected Result: Antiderivative expression (e.g., `(1/3)*x^3`)

---

### 📈 Differential Equations

Numerically solve a differential equation (dy/dx = f(x,y)):

```bash
curl -X POST http://localhost:5000/api/differential/solve \
  -H "Content-Type: application/json" \
  -d '{"function":"x^2","initialConditionY":1,"steps":5}'
```

✅ Expected Response (Approximate Result):

```json
{
  "success": true,
  "result": "0.3333333333333333",
  "executionTimeMs": 15,
  "cpuUsagePercent": 25.50,
  "serviceName": "DifferentialEquationsService"
}
```

Solve ODE with initial conditions and range:

```bash
curl -X POST http://localhost:5000/api/differential/solve \
  -H "Content-Type: application/json" \
  -d '{"function":"x^2","initialConditionX":0,"initialConditionY":0,"range":2,"steps":5}'
```

✅ Note: The `steps` parameter is only required when the equation contains Y (e.g., "dy/dx = y + x"). Otherwise, it represents the range multiplier.

---

### 🔢 Permutations

Generate all permutations of a set (O(n!) time complexity - use small sets):

```bash
curl -X POST http://localhost:5000/api/permutation/generate \
  -H "Content-Type: application/json" \
  -d '{"set":[1,2,3]}'
```

✅ Expected Response (Approximate Result for [1,2,3] = 6 permutations):

```json
{
  "success": true,
  "count": 6,
  "permutations": [[1,2,3], [1,3,2], [2,1,3], [2,3,1], [3,1,2], [3,2,1]],
  "executionTimeMs": 8,
  "cpuUsagePercent": 15.30,
  "serviceName": "PermutationService"
}
```

Ask the AI service to generate a small integer array, then produce all permutations of that array and return a `ServiceResponse` summary.

```bash
curl -X POST http://localhost:5000/api/permutation/generate-from-ai \
  -H "Content-Type: application/json" \ 
  -d '{"count": 3, "minVal": 1, "maxVal": 10, "seed": 42}'
```


✅ Expected Response (Approximate Result for [1,2,3] = 6 permutations):

```json
{
  "success": true,
  "message": "Generated 6 permutations for AI-generated set",
  "data": {
    "originalSet": [2,1,5],
    "permutationCount": 6,
    "firstPermutation": [2,1,5],
    "lastPermutation": [5,2,1]
  },
  "executionTimeMs": 103,
  "cpuUsagePercent": 0,
  "memoryUsageMb": 0.01568603515625,
  "serviceName": "PermutationService",
  "timestamp": "2026-06-05T15:53:25.1314944Z"
}
```

---

### 🔁 Fibonacci (Large Numbers)

Calculate Fibonacci numbers with support for very large n values:

```bash
curl -X POST http://localhost:5000/api/fibonacci/calculate \
  -H "Content-Type: application/json" \
  -d '{"n": 100}'
```

✅ Expected Response (Approximate Result for n=100 = large integer):

```json
{
  "success": true,
  "result": "354224848179261915075",
  "executionTimeMs": 42,
  "cpuUsagePercent": 35.80,
  "serviceName": "FibonacciService"
}
```

---

### 📹 Video Service

Video processing service for compression and frame analysis. Collects CPU and memory metrics during processing.

#### Compress Video
```bash
curl -X POST http://localhost:5000/api/video/compress \
  -F "file=@/path/to/video.mp4"
```

✅ Expected Response (Approximate Result):

```json
{
  "success": true,
  "originalSizeBytes": 52428800,
  "compressedSizeBytes": 15728640,
  "compressionRatio": 0.30,
  "executionTimeMs": 5420,
  "cpuUsagePercent": 85.50,
  "memoryUsageMb": 124.5,
  "serviceName": "VideoService",
  "timestamp": "2026-06-03T21:10:15.1234567Z"
}
```

#### Split Video into Frames
```bash
curl -X POST http://localhost:5000/api/video/split-frames \
  -F "file=@/path/to/video.mp4"
```

---

### 🎨 Digital Filters Service

Image and matrix filtering service using convolution kernels for various filter types.

#### Get Available Filters
```bash
curl http://localhost:5000/api/filters/available
```

✅ Expected Response:

```json
["blur", "sharpen", "edgedetection", "grayscale"]
```

#### Apply Filter to Raw Matrix
```bash
curl -X POST http://localhost:5000/api/filters/apply \
  -H "Content-Type: application/json" \
  -d '{
    "matrix": [[10,20,30],[40,50,60],[70,80,90]],
    "filterType": "blur",
    "startRow": 0,
    "endRow": 3,
    "startCol": 0,
    "endCol": 3
  }'
```

✅ Expected Response (Blur filter reduces intensity variation):

```json
{
  "success": true,
  "resultMatrix": [[20,30,25],[35,50,45],[60,70,65]],
  "executionTimeMs": 12,
  "cpuUsagePercent": 45.20,
  "serviceName": "DigitalFiltersService"
}
```

#### Apply Filter to Image File
```bash
curl -X POST http://localhost:5000/api/filters/apply-image \
  -F "file=@/path/to/image.png" \
  -F "filterType=sharpen"
```

✅ Expected Response: PNG image file stream (processed image)

#### Apply AI-generated Filter (server generates matrix)

Request now contains only the desired filter name and kernel size. The service will ask the AI to generate an NxN integer matrix (AI does not receive the filter type), then apply the requested filter locally.

```bash
curl -X POST http://localhost:5000/api/filters/apply-ai-matrix \
  -H "Content-Type: application/json" \
  -d '{
    "filterName": "blur",
    "kernelSize": 3
  }'
```

✅ Expected Response:

```json
{
  "processedMatrix": [[20,30,25],[35,50,45],[60,70,65]],
  "filterApplied": "blur",
  "processedAt": "2026-06-07T02:26:05.282Z"
}
```

Notes:
- The AI is asked only for a numeric matrix of the given size. The server clamps matrix values to 0..255 before applying the filter.
- If AI cannot produce a matrix, the endpoint will return an HTTP 500 with an explanatory error message; check service logs for AI payload details.

### 🔢 AI Service

AI-powered data generation service for random numbers and synthetic image generation.

Generate random numbers:
```bash
curl -X POST http://localhost:5000/api/Ai/generate \
  -H "Content-Type: application/json" \
  -d '{"user_input": "Give me 10 random numbers between 1 and 100 with seed 42"}'
```

✅ Expected Response:

```json
{
  "success": true,
  "result": [42, 81, 15, 92, 38, 56, 7, 88, 23, 61],
  "executionTimeMs": 25,
  "serviceName": "AiService"
}
```

Generate synthetic image:
```bash
curl -X POST http://localhost:5000/api/Ai/generate \
  -H "Content-Type: application/json" \
  -d '{"user_input": "Generate an image with seed 42 width 512 height 512"}'
```

✅ Expected Response:

```json
{
  "success": true,
  "imageName": "generated_42_512_512.png",
  "executionTimeMs": 156,
  "serviceName": "AiService"
}
```

Retrieve generated image:
```bash
curl http://localhost:5000/api/Ai/image/generated_42_512_512.png
```

✅ Expected Response: Base64-encoded PNG image or image data

## 🛠️ Troubleshooting

### If Pods stucked in pulling images

```bash
ansible workers -i inventory.ini -b -m systemd -a "name=containerd state=restarted"
```

### If Stucked on terminating
```bash
ansible workers -i inventory.ini -b -m systemd -a "name=containerd state=restarted"
```

### ❌ Port Already in Use

**Problem**: "Address already in use" error when starting a service

**Solution**: Change the port in `launchSettings.json` or use environment variables:

```bash
# Start on a different port
dotnet run --urls "http://localhost:5008"
```

Alternatively, kill the process using the port:
```bash
# On Linux/Mac
sudo lsof -i :5006
sudo kill -9 <PID>

# On Windows
netstat -ano | findstr :5006
taskkill /PID <PID> /F
```

**Prevention in containers**: Use service discovery (DNS names like `http://video-service:5006`) instead of hardcoded `localhost`.

---

### ⚠️ 502 / 503 Errors (Service Unavailable)

**Problem**: Gateway returns "Bad Gateway" or "Service Unavailable"

**Common Causes**:
1. Backend service not running
2. Port mismatch between gateway config and service
3. Service crashed due to invalid input

**Debugging**:
```bash
# Check if service is responding
curl http://localhost:5006/health

# Check gateway logs for service addresses
# In Gateway/appsettings.json, verify all service URLs

# Check service logs for errors
dotnet run --project VideoService/VideoService.csproj
```

**Example Error Flow**:
```
Request: curl http://localhost:5000/api/video/compress ...
↓
Gateway routes to: http://localhost:5006
↓
If 5006 not running → 502 Bad Gateway
↓
Solution: Start VideoService on port 5006
```

**In containers**: Use service DNS names instead of localhost - the container orchestrator handles discovery.

---

### 🌐 IPv6 Issues

**Problem**: Address family not supported errors or connection timeouts

**Solution**: Disable IPv6 for .NET:

```bash
# Linux/Mac
export DOTNET_SYSTEM_NET_DISABLEIPV6=1
dotnet run

# Windows
set DOTNET_SYSTEM_NET_DISABLEIPV6=1
dotnet run
```

Or add to launchSettings.json:
```json
"environmentVariables": {
  "ASPNETCORE_ENVIRONMENT": "Development",
  "DOTNET_SYSTEM_NET_DISABLEIPV6": "1"
}
```

---

### 📉 Unsupported Functions

**Problem**: "Function not supported" or calculation errors

**Supported Mathematical Functions**:

| Category | Functions | Examples |
|----------|-----------|----------|
| **Polynomials** | `x^n` where n is an integer | `x^2`, `x^3`, `x^0.5` |
| **Trigonometric** | `sin`, `cos`, `tan` | `sin(x)`, `cos(2*x)` |
| **Exponential/Log** | `exp`, `ln`, `log` | `exp(x)`, `ln(x)` |
| **Rational** | `1/x`, `1/(x^2)` | Division by zero causes error |
| **Constants** | `pi`, `e` | Work with trig/exp functions |

**Supported Operations**:
- Addition: `x + 1`
- Subtraction: `x - 1`
- Multiplication: `x * 2` or `2x`
- Division: `1/x`
- Exponentiation: `x^2`
- Composition: `sin(x^2 + 1)`

**NOT Supported**:
- Piecewise functions: `if x > 0 then x else -x`
- Implicit equations: `x^2 + y^2 = 1`
- Higher-order derivatives
- Inverse functions as notation: `x^(-1)` should be `1/x`

**Workarounds**:
```bash
# WRONG: x^(-1)
# RIGHT: 1/x

# WRONG: arcsin(x)
# RIGHT: Use Integration/Antiderivative for related calculations

# WRONG: |x| (absolute value)
# RIGHT: Use x if x > 0, otherwise approximate with x^2 or use sqrt(x^2)
```

**Error Examples**:
```bash
# This works:
{"function":"x^2+2*sin(x)","lowerBound":0,"upperBound":1,"steps":1000}

# This fails:
{"function":"if x>0 then x else 0","lowerBound":0,"upperBound":1,"steps":1000}
# Error: Function parsing not supported for conditional logic

# This works:
{"function":"1/x","lowerBound":0.1,"upperBound":1,"steps":1000}

# This fails:
{"function":"1/x","lowerBound":-1,"upperBound":1,"steps":1000}
# Error: Division by zero at x=0
```

---

## ⚙️ Configuration Notes

* **Routing**: `Gateway/appsettings.json`
* **Ports**: `launchSettings.json`
* **Shared DTOs**: `SharedModels`

## Configuration required for AI integration (important)

The PermutationService calls the AI service through a typed `HttpClient` whose base address is read from configuration. In production you must provide the AI service base URL via configuration or environment variable — otherwise the service will fall back to a local default.

Why
- The code reads configuration key `AiService:BaseUrl` (or environment variable `AI_SERVICE_BASEURL`) and registers a typed `HttpClient<AiServiceClient>` with that base address.
- Do not hardcode `localhost` in production. Set the correct URL (gateway or service DNS) for your environment.

Options to configure

1) Set an environment variable (recommended for containers / cloud)
- Linux / macOS:
```bash
export AiService__BaseUrl="http://ai-service:5005"
```
- Windows:
```cmd
set AiService__BaseUrl=http://ai-service:5005
```
