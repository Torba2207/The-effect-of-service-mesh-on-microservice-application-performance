using Microsoft.AspNetCore.Mvc;
using DifferentialService.Services;
using SharedModels.Models;

namespace DifferentialService.Controllers;

[ApiController]
[Route("api/[controller]")]
public class DifferentialController(DifferentialCalculator calculator, ILogger<DifferentialController> logger) : ControllerBase
{
    private const string ServiceName = "DifferentialEquationsService";

    [HttpPost("solve")]
    public async Task<ActionResult<ServiceResponse>> Calculate([FromBody] DifferentialRequest request)
    {
        logger.LogInformation(
            "Differential solution requested: {Function} with x0 = {InitialConditionX}, y0 = {InitialConditionY}" + 
            ", range = {Range} and step param of {Steps}", request.Function, request.InitialConditionX,
            request.InitialConditionY, request.Range, request.Steps
        );
        // --- Pre-Work Metrics ---
        var process = System.Diagnostics.Process.GetCurrentProcess();
        long startTick = System.Diagnostics.Stopwatch.GetTimestamp(); // High-res timer[cite: 4]
        TimeSpan startCpuTime = process.TotalProcessorTime;
        long startMemory = GC.GetTotalMemory(false);

        var response = new ServiceResponse { ServiceName = ServiceName };

        try
        {
            // --- The Workload (Now abstracted) ---
            string finalExpr = await calculator.SolveAsync(request);

            // --- Post-Work Metrics ---
            TimeSpan elapsed = System.Diagnostics.Stopwatch.GetElapsedTime(startTick);
            TimeSpan endCpuTime = process.TotalProcessorTime;
            long endMemory = GC.GetTotalMemory(false);

            // CPU usage calculation relative to real-time and core count[cite: 4]
            double cpuUsedMs = (endCpuTime - startCpuTime).TotalMilliseconds;
            double totalMs = elapsed.TotalMilliseconds;
            double cpuPercent = (cpuUsedMs / (Environment.ProcessorCount * totalMs)) * 100;

            response.Success = true;
            response.Data = new { FinalExpression = finalExpr };
            response.ExecutionTimeMs = (long)totalMs;
            response.CpuUsagePercent = Math.Round(cpuPercent, 2);
            response.MemoryUsageMb = Math.Round((endMemory - startMemory) / 1024.0 / 1024.0, 2);
            response.Message = "Calculation successful.";
        }
        catch (Exception ex)
        {
            response.Success = false;
            response.Message = ex.Message;
        }

        return Ok(response);
    }
}