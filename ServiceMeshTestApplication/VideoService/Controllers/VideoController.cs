using Microsoft.AspNetCore.Mvc;
using SharedModels.Models;
using System.Diagnostics;
using VideoService.Services;

namespace VideoService.Controllers;

[ApiController]
[Route("api/[controller]")]
public class VideoController : ControllerBase
{
    private readonly VideoProcessor _videoProcessor;
    private readonly Process _currentProcess;

    public VideoController(VideoProcessor videoProcessor)
    {
        _videoProcessor = videoProcessor;
        _currentProcess = Process.GetCurrentProcess();
    }

    [HttpPost("compress")]
    public async Task<ActionResult<ServiceResponse>> CompressVideo(IFormFile file)
    {
        var stopwatch = Stopwatch.StartNew();
        var initialCpu = _currentProcess.TotalProcessorTime;
        var initialMemory = _currentProcess.WorkingSet64 / (1024.0 * 1024.0);

        try
        {
            if (file == null || file.Length == 0)
            {
                return BadRequest(new ServiceResponse
                {
                    Success = false,
                    Message = "No file uploaded",
                    ServiceName = "VideoService",
                    ExecutionTimeMs = stopwatch.ElapsedMilliseconds
                });
            }

            using var stream = file.OpenReadStream();
            var result = await _videoProcessor.CompressVideo(stream, file.FileName);

            stopwatch.Stop();
            var finalCpu = _currentProcess.TotalProcessorTime;
            var finalMemory = _currentProcess.WorkingSet64 / (1024.0 * 1024.0);
            var cpuUsed = (finalCpu - initialCpu).TotalMilliseconds;
            var cpuUsagePercent = cpuUsed / stopwatch.Elapsed.TotalMilliseconds * 100.0 / Environment.ProcessorCount;

            return Ok(new ServiceResponse
            {
                Success = true,
                Message = "Video compressed successfully",
                Data = result,
                ExecutionTimeMs = stopwatch.ElapsedMilliseconds,
                CpuUsagePercent = cpuUsagePercent,
                MemoryUsageMb = finalMemory - initialMemory,
                ServiceName = "VideoService"
            });
        }
        catch (Exception ex)
        {
            stopwatch.Stop();
            return StatusCode(500, new ServiceResponse
            {
                Success = false,
                Message = $"Error compressing video: {ex.Message}",
                ExecutionTimeMs = stopwatch.ElapsedMilliseconds,
                ServiceName = "VideoService"
            });
        }
    }

    [HttpPost("split-frames")]
    public async Task<ActionResult<ServiceResponse>> SplitFrames(IFormFile file)
    {
        var stopwatch = Stopwatch.StartNew();
        var initialCpu = _currentProcess.TotalProcessorTime;
        var initialMemory = _currentProcess.WorkingSet64 / (1024.0 * 1024.0);

        try
        {
            if (file == null || file.Length == 0)
            {
                return BadRequest(new ServiceResponse
                {
                    Success = false,
                    Message = "No file uploaded",
                    ServiceName = "VideoService",
                    ExecutionTimeMs = stopwatch.ElapsedMilliseconds
                });
            }

            using var stream = file.OpenReadStream();
            var result = await _videoProcessor.SplitFrames(stream, file.FileName);

            stopwatch.Stop();
            var finalCpu = _currentProcess.TotalProcessorTime;
            var finalMemory = _currentProcess.WorkingSet64 / (1024.0 * 1024.0);
            var cpuUsed = (finalCpu - initialCpu).TotalMilliseconds;
            var cpuUsagePercent = cpuUsed / stopwatch.Elapsed.TotalMilliseconds * 100.0 / Environment.ProcessorCount;

            return Ok(new ServiceResponse
            {
                Success = true,
                Message = "Frames extracted successfully",
                Data = result,
                ExecutionTimeMs = stopwatch.ElapsedMilliseconds,
                CpuUsagePercent = cpuUsagePercent,
                MemoryUsageMb = finalMemory - initialMemory,
                ServiceName = "VideoService"
            });
        }
        catch (Exception ex)
        {
            stopwatch.Stop();
            return StatusCode(500, new ServiceResponse
            {
                Success = false,
                Message = $"Error splitting frames: {ex.Message}",
                ExecutionTimeMs = stopwatch.ElapsedMilliseconds,
                ServiceName = "VideoService"
            });
        }
    }
}