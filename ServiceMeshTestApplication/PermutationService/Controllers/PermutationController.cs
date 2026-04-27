using Microsoft.AspNetCore.Mvc;
using PermutationService.Services;
using SharedModels.Models;

namespace PermutationService.Controllers;

[ApiController]
[Route("api/[controller]")]
public class PermutationController(PermutationCalculator calculator, ILogger<PermutationController> logger) : ControllerBase
{
    [HttpPost("generate")]
    public async Task<ActionResult<ServiceResponse>> GeneratePermutations([FromBody] PermutationsRequest request)
    {
        logger.LogInformation("Permutations requested for set of size {Size}", request.Set.Length);

        if (request.Set.Length == 0)
        {
            return BadRequest(new ServiceResponse
            {
                Success = false,
                Message = "Set cannot be empty"
            });
        }

        if (request.Set.Length > 10)
        {
            return BadRequest(new ServiceResponse
            {
                Success = false,
                Message = "Set size must be ≤ 10 (O(n!) complexity)"
            });
        }

        try
        {
            var (permutations, execTimeMs, cpuUsage, memoryMb) = await Task.Run(() =>
                calculator.GetAllPermutations(request.Set));

            return Ok(new ServiceResponse
            {
                Success = true,
                Message = $"Generated {permutations.Count} permutations for the given set",
                ExecutionTimeMs = execTimeMs,
                CpuUsagePercent = cpuUsage,
                MemoryUsageMb = memoryMb,
                ServiceName = "PermutationService",
                Data = new
                {
                    OriginalSet = request.Set,
                    PermutationCount = permutations.Count,
                    FirstPermutation = permutations.FirstOrDefault(),
                    LastPermutation = permutations.LastOrDefault()
                }
            });
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Error generating permutations");
            return StatusCode(500, new ServiceResponse
            {
                Success = false,
                Message = $"Error: {ex.Message}",
                ServiceName = "PermutationService"
            });
        }
    }
}