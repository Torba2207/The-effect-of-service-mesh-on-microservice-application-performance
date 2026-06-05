using System.Text.Json;
using Microsoft.AspNetCore.Mvc;
using PermutationService.Services;
using SharedModels.Models;

namespace PermutationService.Controllers;

[ApiController]
[Route("api/[controller]")]
public class PermutationController(PermutationCalculator calculator, AiServiceClient aiClient, ILogger<PermutationController> logger) : ControllerBase
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

    [HttpPost("generate-from-ai")]
    public async Task<ActionResult<ServiceResponse>> GenerateFromAi([FromBody] PermutationsFromAiRequest request)
    {
        logger.LogInformation("Permutations requested from AI: count={Count}, range={Min}-{Max}, seed={Seed}",
            request.Count, request.MinVal, request.MaxVal, request.Seed);

        if (request.Count <= 0 || request.Count > 10)
        {
            return BadRequest(new ServiceResponse
            {
                Success = false,
                Message = "Count must be between 1 and 10 (avoid explosion of permutations)."
            });
        }

        try
        {
            var generated = await aiClient.GenerateRandomArrayAsync(request.Count, request.MinVal, request.MaxVal, request.Seed);

            if (generated == null || generated.Length == 0)
            {
                return StatusCode(502, new ServiceResponse
                {
                    Success = false,
                    Message = "AI service returned no data",
                    ServiceName = "PermutationService"
                });
            }

            logger.LogInformation("AI returned array: {@Array}", generated);

            var (permutations, execTimeMs, cpuUsage, memoryMb) = await Task.Run(() =>
                calculator.GetAllPermutations(generated));

            return Ok(new ServiceResponse
            {
                Success = true,
                Message = $"Generated {permutations.Count} permutations for AI-generated set",
                ExecutionTimeMs = execTimeMs,
                CpuUsagePercent = cpuUsage,
                MemoryUsageMb = memoryMb,
                ServiceName = "PermutationService",
                Data = new
                {
                    OriginalSet = generated,
                    PermutationCount = permutations.Count,
                    FirstPermutation = permutations.FirstOrDefault(),
                    LastPermutation = permutations.LastOrDefault()
                }
            });
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Error generating permutations from AI");
            return StatusCode(500, new ServiceResponse
            {
                Success = false,
                Message = $"Error: {ex.Message}",
                ServiceName = "PermutationService"
            });
        }
    }
}