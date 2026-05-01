using Microsoft.AspNetCore.Mvc;
using DigitalFiltersService.Filters;
using SharedModels;

namespace DigitalFiltersService.Controllers;

[ApiController]
[Route("api/[controller]")]
public class FiltersController : ControllerBase
{
    private readonly ILogger<FiltersController> _logger;

    public FiltersController(ILogger<FiltersController> logger)
    {
        _logger = logger;
    }

    [HttpPost("apply")]
    public ActionResult<FilterResponse> ApplyFilter([FromBody] FilterRequest request)
    {
        try
        {
            if (request.Matrix == null || request.Matrix.Length == 0)
            {
                return BadRequest(new { error = "Matrix cannot be null or empty" });
            }

            int rows = request.Matrix.GetLength(0);
            int cols = request.Matrix.GetLength(1);

            // Set default end bounds if not specified
            if (request.EndRow == 0) request.EndRow = rows;
            if (request.EndCol == 0) request.EndCol = cols;

            byte[,] processedMatrix = request.FilterType.ToLowerInvariant() switch
            {
                "blur" => MatrixFilter.ApplyBlurFilter(request.Matrix, request.StartRow, request.EndRow, request.StartCol, request.EndCol),
                "sharpen" => MatrixFilter.ApplySharpenFilter(request.Matrix, request.StartRow, request.EndRow, request.StartCol, request.EndCol),
                "edgedetection" or "edge" => MatrixFilter.ApplyEdgeDetectionFilter(request.Matrix, request.StartRow, request.EndRow, request.StartCol, request.EndCol),
                "grayscale" => MatrixFilter.ApplyGrayscaleFilter(request.Matrix, request.StartRow, request.EndRow, request.StartCol, request.EndCol),
                _ => throw new ArgumentException($"Unknown filter type: {request.FilterType}")
            };

            _logger.LogInformation("Applied {FilterType} filter to matrix ({Rows}x{Cols})", 
                request.FilterType, rows, cols);

            return Ok(new FilterResponse
            {
                ProcessedMatrix = processedMatrix,
                FilterApplied = request.FilterType
            });
        }
        catch (ArgumentException ex)
        {
            _logger.LogWarning(ex, "Invalid filter request");
            return BadRequest(new { error = ex.Message });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error processing filter request");
            return StatusCode(500, new { error = "Internal server error" });
        }
    }

    [HttpGet("available")]
    public ActionResult<IEnumerable<string>> GetAvailableFilters()
    {
        return Ok(new[] { "blur", "sharpen", "edgedetection", "grayscale" });
    }
}