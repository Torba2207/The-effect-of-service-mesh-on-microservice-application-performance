using Microsoft.AspNetCore.Mvc;
using IntegrationService.Services;
using SharedModels.Models;

namespace IntegrationService.Controllers;

[ApiController]
[Route("api/[controller]")]
public class IntegrationController(IntegralCalculator calculator, ILogger<IntegrationController> logger) : ControllerBase
{
    [HttpPost("calculate")]
    public async Task<ActionResult<ServiceResponse>> Calculate([FromBody] IntegrationRequest request)
    {
        logger.LogInformation("Integration requested: {Function} from {Lower} to {Upper}, steps={Steps}",
            request.Function, request.LowerBound, request.UpperBound, request.Steps);

        var supported = new[] { "x^2", "sin", "cos", "exp", "1/x" };
        if (!supported.Contains(request.Function.ToLower()))
        {
            return BadRequest(new ServiceResponse
            {
                Success = false,
                Message = $"Function '{request.Function}' not supported. Use: {string.Join(", ", supported)}"
            });
        }

        try
        {
            var (result, execTimeMs, cpuUsage) = await Task.Run(() =>
                calculator.CalculateIntegral(request.Function, request.LowerBound, request.UpperBound, request.Steps));

            return Ok(new ServiceResponse
            {
                Success = true,
                Message = "Integral calculated successfully",
                ExecutionTimeMs = execTimeMs,
                CpuUsagePercent = cpuUsage,
                ServiceName = "IntegrationService",
                Data = new
                {
                    request.Function,
                    request.LowerBound,
                    request.UpperBound,
                    request.Steps,
                    Result = result
                }
            });
        }
        catch (NotSupportedException ex)
        {
            return BadRequest(new ServiceResponse { Success = false, Message = ex.Message });
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Error calculating integral");
            return StatusCode(500, new ServiceResponse
            {
                Success = false,
                Message = $"Error: {ex.Message}",
                ServiceName = "IntegrationService"
            });
        }
    }
}