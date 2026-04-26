using Microsoft.AspNetCore.Mvc;
using VideoService.Services;

namespace VideoService.Controllers;

[ApiController]
[Route("api/[controller]")]
public class VideoController : ControllerBase
{
    private readonly VideoProcessor _videoProcessor;
    private readonly DigitalFiltersClient _digitalFiltersClient;

    public VideoController(VideoProcessor videoProcessor, DigitalFiltersClient digitalFiltersClient)
    {
        _videoProcessor = videoProcessor;
        _digitalFiltersClient = digitalFiltersClient;
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

        var filterApplied = await _digitalFiltersClient.ApplyFilter("compression", 0);

        return Ok(new
        {
            Compression = result,
            DigitalFilterResponse = filterApplied
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

        var filterApplied = await _digitalFiltersClient.ApplyFilter("frame-split", result.FrameCount);

        return Ok(new
        {
            FrameSplit = result,
            DigitalFilterResponse = filterApplied
        });
    }
}