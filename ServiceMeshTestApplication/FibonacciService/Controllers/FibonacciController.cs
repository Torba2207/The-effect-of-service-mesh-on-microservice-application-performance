using Microsoft.AspNetCore.Mvc;
using FibonacciService.Services;
using SharedModels.Models;

namespace FibonacciService.Controllers;

[ApiController]
[Route("api/[controller]")]
public class FibonacciController(FibonacciCalculator calculator, ILogger<FibonacciController> logger) : ControllerBase
{
    [HttpPost("calculate")]
    public async Task<ActionResult<ServiceResponse>> CalculateFibonacci([FromBody] FibonacciRequest request)
    {
        logger.LogInformation("Fibonacci requested for n = {N}", request.N);

        if (request.N < 0)
        {
            return BadRequest(new ServiceResponse
            {
                Success = false,
                Message = "N must be non-negative"
            });
        }

        try
        {
            var (result, execTimeMs, cpuUsage) = await Task.Run(() =>
                calculator.CalculateFibonacci(request.N));

            return Ok(new ServiceResponse
            {
                Success = true,
                Message = $"Fibonacci({request.N}) calculated successfully",
                ExecutionTimeMs = execTimeMs,
                CpuUsagePercent = cpuUsage,
                ServiceName = "FibonacciService",
                Data = new
                {
                    request.N,
                    Result = result.ToString(),
                    DigitCount = result.ToString().Length
                }
            });
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Error calculating Fibonacci number");
            return StatusCode(500, new ServiceResponse
            {
                Success = false,
                Message = $"Error: {ex.Message}",
                ServiceName = "FibonacciService"
            });
        }
    }
}