using Microsoft.AspNetCore.Mvc;
using VideoService.Services;

namespace VideoService.Controllers;

[ApiController]
[Route("api/[controller]")]
public class VideoController : ControllerBase
{
    private readonly VideoProcessor _videoProcessor;

    public VideoController(VideoProcessor videoProcessor)
    {
        _videoProcessor = videoProcessor;
    }

    [HttpPost("compress")]
    public async Task<IActionResult> CompressVideo(IFormFile file)
    {
        if (file == null || file.Length == 0)
        {
            return BadRequest("No file uploaded");
        }

        using var stream = file.OpenReadStream();
        var result = await _videoProcessor.CompressVideo(stream, file.FileName);

        return Ok(new
        {
            Compression = result
        });
    }

    [HttpPost("split-frames")]
    public async Task<IActionResult> SplitFrames(IFormFile file)
    {
        if (file == null || file.Length == 0)
        {
            return BadRequest("No file uploaded");
        }

        using var stream = file.OpenReadStream();
        var result = await _videoProcessor.SplitFrames(stream, file.FileName);

        return Ok(new
        {
            FrameSplit = result
        });
    }

    [HttpGet("test")]
    public async Task<IActionResult> Test()
    {
        return Ok(new
        {
            DigitalFiltersServiceHealthy = 1.0
        });
    }   
}