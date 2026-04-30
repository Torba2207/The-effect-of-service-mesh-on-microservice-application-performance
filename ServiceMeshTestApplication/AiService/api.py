from fastapi import FastAPI, HTTPException, Response
from fastapi.responses import JSONResponse
from pydantic import BaseModel
import uvicorn
import base64
import os
from langchain_mcp_adapters.client import MultiServerMCPClient
from langchain_ollama import ChatOllama
from langchain_core.messages import HumanMessage, ToolMessage, SystemMessage
import subprocess
import requests
from datetime import datetime, timezone
import json
import psutil
import time

app = FastAPI(title="Procedural Generation API")

class ChatRequest(BaseModel):
    user_input: str

# ---------------------------------------------------------
# TELEMETRY HELPERS (Data Collection Only)
# ---------------------------------------------------------
def start_telemetry() -> float:
    """Primes the CPU monitor and starts the execution timer."""
    psutil.cpu_percent(interval=None)
    return time.perf_counter()

def finalize_telemetry(start_time: float):
    """
    Gathers hardware metrics and returns the raw variables needed 
    for the endpoints to construct their own payloads.
    """
    cpu_percent = round(psutil.cpu_percent(interval=None), 2)
    
    api_mem_mb, server_mem_mb, model_mem_mb = 0.0, 0.0, 0.0

    # Scan the processes for exact memory footprints
    for proc in psutil.process_iter(['pid', 'cmdline', 'memory_info']):
        try:
            cmd = " ".join(proc.info['cmdline'] or [])
            mem_mb = proc.info['memory_info'].rss / (1024 * 1024)

            if proc.pid == os.getpid():
                api_mem_mb = mem_mb
            elif "python server.py" in cmd:
                server_mem_mb = mem_mb
            elif "ollama runner" in cmd or "ollama serve" in cmd:
                model_mem_mb += mem_mb
        except (psutil.NoSuchProcess, psutil.AccessDenied, psutil.ZombieProcess):
            continue

    exec_time_ms = round((time.perf_counter() - start_time) * 1000, 2)
    total_mem_mb = round(model_mem_mb + server_mem_mb + api_mem_mb, 2)
    
    # Pre-format the RAM breakdown message
    ram_message = f"RAM for parts: model ({round(model_mem_mb, 2)}), MCP({round(server_mem_mb, 2)}), api ({round(api_mem_mb, 2)})"
    timestamp = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")

    return exec_time_ms, cpu_percent, str(total_mem_mb), ram_message, timestamp

# ---------------------------------------------------------
# THE LLM ROUTER (The "Agentic Loop")
# ---------------------------------------------------------
async def run_agentic_loop(user_input: str, llm_with_tools, tools):
    system_rules = """
      You are a highly efficient API routing assistant.
      Your ONLY job is to analyze the user's request and trigger the correct tool.
      You MUST NOT attempt to generate the image or number line yourself.
      Always extract seed, width and height for image generation.
      Always extract seed, count, min and max for random number generation.
      Return THE EXACT SAME STRING you get from the tool, DO NOT add anything else to the answer.
    """
    messages = [
        SystemMessage(content=system_rules),
        HumanMessage(content=user_input)
    ]

    while True:
        ai_msg = await llm_with_tools.ainvoke(messages)
        messages.append(ai_msg)

        if not ai_msg.tool_calls:
            return ai_msg.content

        for tool_call in ai_msg.tool_calls:
            try:
                selected_tool = next(t for t in tools if t.name == tool_call["name"])
                tool_result = await selected_tool.ainvoke(tool_call["args"])
                text_output = tool_result[0]["text"]

                try:
                    parsed_data = json.loads(text_output)
                    return parsed_data
                except json.JSONDecodeError:
                    return text_output
            except StopIteration:
                return f"Error: Tool {tool_call['name']} not found."

# ---------------------------------------------------------
# ENDPOINTS (Data Formatting)
# ---------------------------------------------------------
@app.post("/ai/generate")
async def generate_endpoint(request: ChatRequest):
    start_time = start_telemetry()
    try:
        llm = ChatOllama(model=os.getenv("TARGET_MODEL", "llama3.2"), temperature=0.0)
        client = MultiServerMCPClient({
            "procedural_server": {
                "transport": "sse",
                "url": "http://127.0.0.1:8000/sse",
            }
        })
        tools = await client.get_tools()
        llm_with_tools = llm.bind_tools(tools)
        
        final_answer = await run_agentic_loop(request.user_input, llm_with_tools, tools)

        # Retrieve raw telemetry variables
        exec_ms, cpu, total_mem, ram_msg, timestamp = finalize_telemetry(start_time)

        return {
            "Success": True,
            "Message": ram_msg,
            "Data": final_answer,
            "ExecutionTimeMS": exec_ms,
            "CpuUsagePercent": cpu,
            "MemoryUsageMB": total_mem,
            "ServiceName": "AIService",
            "Timestamp": timestamp
        }

    except Exception as e:
        exec_ms, cpu, total_mem, ram_msg, timestamp = finalize_telemetry(start_time)
        return JSONResponse(status_code=500, content={
            "Success": False,
            "Message": f"Server Error: {str(e)} | {ram_msg}",
            "Data": None,
            "ExecutionTimeMS": exec_ms,
            "CpuUsagePercent": cpu,
            "MemoryUsageMB": total_mem,
            "ServiceName": "AIService",
            "Timestamp": timestamp
        })

@app.get("/ai/image/{image_filename}")
def image_acquisition_endpoint(image_filename: str):
    start_time = start_telemetry()
    try:
        with open(f"data/img/{image_filename}", "rb") as image_file:
            encoded_bytes = base64.b64encode(image_file.read())
            base64_string = encoded_bytes.decode('utf-8')
            os.remove(f"data/img/{image_filename}")
            
            exec_ms, cpu, total_mem, ram_msg, timestamp = finalize_telemetry(start_time)

            return {
                "Success": True,
                "Message": "Image successfully loaded and encoded.",
                "Data": base64_string,
                "ExecutionTimeMS": exec_ms,
                "CpuUsagePercent": cpu,
                "MemoryUsageMB": total_mem,
                "ServiceName": "AIService",
                "Timestamp": timestamp
            }

    except FileNotFoundError:
        exec_ms, cpu, total_mem, ram_msg, timestamp = finalize_telemetry(start_time)
        return JSONResponse(status_code=404, content={
            "Success": False,
            "Message": f"Image '{image_filename}' not found.",
            "Data": None,
            "ExecutionTimeMS": exec_ms,
            "CpuUsagePercent": cpu,
            "MemoryUsageMB": total_mem,
            "ServiceName": "AIService",
            "Timestamp": timestamp
        })
    except Exception as e:
        exec_ms, cpu, total_mem, ram_msg, timestamp = finalize_telemetry(start_time)
        return JSONResponse(status_code=500, content={
            "Success": False,
            "Message": f"Error processing image: {str(e)}",
            "Data": None,
            "ExecutionTimeMS": exec_ms,
            "CpuUsagePercent": cpu,
            "MemoryUsageMB": total_mem,
            "ServiceName": "AIService",
            "Timestamp": timestamp
        })

@app.get("/ai/health")
def deep_health_check():
    api_status = "healthy"
    mcp_status = "dead"
    ollama_status = "dead"

    try:
        process_list = subprocess.check_output(["ps", "aux"]).decode("utf-8")
        if "python server.py" in process_list:
            mcp_status = "healthy"
    except Exception:
        mcp_status = "error"

    try:
        res = requests.get("http://127.0.0.1:11434/api/tags", timeout=2)
        if res.status_code == 200:
            ollama_status = "healthy"
    except Exception:
        ollama_status = "unreachable"

    status_string = f"api ({api_status}) - mcp ({mcp_status}) - ollama ({ollama_status})"
    timestamp = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")

    response_payload = {
        "service": "AIService",
        "status": status_string,
        "timestamp": timestamp
    }

    if mcp_status == "healthy" and ollama_status == "healthy":
        return response_payload
    else:
        return Response(
            content=json.dumps(response_payload), 
            status_code=503,
            media_type="application/json"
        )

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=5005)