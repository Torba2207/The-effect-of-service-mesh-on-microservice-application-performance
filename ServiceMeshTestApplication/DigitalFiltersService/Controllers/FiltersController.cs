using DigitalFiltersService.Filters;
using DigitalFiltersService.Services;
using Microsoft.AspNetCore.Mvc;
using SharedModels;
using SixLabors.ImageSharp;
using SixLabors.ImageSharp.PixelFormats;

namespace DigitalFiltersService.Controllers;

[ApiController]
[Route("api/[controller]")]
public class FiltersController : ControllerBase
{
    private readonly AiServiceClient _aiClient;

    public FiltersController(AiServiceClient aiClient)
    {
        _aiClient = aiClient;
    }

    [HttpPost("apply-ai-matrix")]
    public async Task<ActionResult<FilterResponse>> ApplyAiMatrix([FromBody] CustomMatrixFilterRequest request, CancellationToken ct)
    {
        try
        {
            if (request.KernelSize <= 0 || request.KernelSize % 2 == 0)
            {
                return BadRequest(new { error = "Kernel size must be a positive odd number (e.g., 3, 5, 7)." });
            }

            // Generate a matrix from AI (AI should only receive matrix size)
            int[][] aiMatrix = await _aiClient.GenerateFilterMatrixAsync(request.KernelSize, ct);

            // Clamp AI values into 0..255 and convert to byte[,] for filtering
            var clamped = aiMatrix.Select(r => r.Select(v => Math.Clamp(v, 0, 255)).ToArray()).ToArray();
            var input2D = JaggedTo2D(clamped);

            int rows = input2D.GetLength(0);
            int cols = input2D.GetLength(1);

            byte[,] processed2D = request.FilterName.ToLowerInvariant() switch
            {
                "blur" => MatrixFilter.ApplyBlurFilter(input2D, 0, rows, 0, cols),
                "sharpen" => MatrixFilter.ApplySharpenFilter(input2D, 0, rows, 0, cols),
                "edgedetection" or "edge" => MatrixFilter.ApplyEdgeDetectionFilter(input2D, 0, rows, 0, cols),
                "grayscale" => MatrixFilter.ApplyGrayscaleFilter(input2D, 0, rows, 0, cols),
                _ => throw new ArgumentException($"Unknown filter type: {request.FilterName}")
            };

            var processedJagged = ToJagged(processed2D);

            return Ok(new FilterResponse
            {
                ProcessedMatrix = processedJagged,
                FilterApplied = request.FilterName,
                ProcessedAt = DateTime.UtcNow
            });
        }
        catch (ArgumentException ex)
        {
            return BadRequest(new { error = ex.Message });
        }
        catch (Exception ex)
        {
            return StatusCode(500, new { error = "Internal runtime error" });
        }
    }

    private static byte[,] ApplyConvolution(byte[,] input, int[][] kernel, int startRow, int endRow, int startCol, int endCol)
    {
        int imageRows = input.GetLength(0);
        int imageCols = input.GetLength(1);
        byte[,] output = (byte[,])input.Clone();

        int kSize = kernel.Length;
        int radius = kSize / 2;

        int kernelSum = 0;
        for (int i = 0; i < kSize; i++)
        {
            for (int j = 0; j < kSize; j++)
                kernelSum += kernel[i][j];
        }
        if (kernelSum == 0) kernelSum = 1;

        for (int r = startRow; r < endRow; r++)
        {
            for (int c = startCol; c < endCol; c++)
            {
                if (r < radius || r >= imageRows - radius || c < radius || c >= imageCols - radius)
                    continue;

                int pixelCalculation = 0;

                for (int kr = 0; kr < kSize; kr++)
                {
                    for (int kc = 0; kc < kSize; kc++)
                    {
                        int targetRow = r + (kr - radius);
                        int targetCol = c + (kc - radius);

                        pixelCalculation += input[targetRow, targetCol] * kernel[kr][kc];
                    }
                }

                int normalizedResult = pixelCalculation / kernelSum;
                output[r, c] = (byte)Math.Clamp(normalizedResult, 0, 255);
            }
        }

        return output;
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

            int rows = request.Matrix.Length;
            int cols = request.Matrix[0].Length;
            for (int r = 1; r < rows; r++)
            {
                if (request.Matrix[r].Length != cols)
                    return BadRequest(new { error = "All rows in the matrix must have the same length" });
            }

            if (request.EndRow == 0) request.EndRow = rows;
            if (request.EndCol == 0) request.EndCol = cols;

            var input2D = JaggedTo2D(request.Matrix);

            byte[,] processed2D = request.FilterType.ToLowerInvariant() switch
            {
                "blur" => MatrixFilter.ApplyBlurFilter(input2D, request.StartRow, request.EndRow, request.StartCol, request.EndCol),
                "sharpen" => MatrixFilter.ApplySharpenFilter(input2D, request.StartRow, request.EndRow, request.StartCol, request.EndCol),
                "edgedetection" or "edge" => MatrixFilter.ApplyEdgeDetectionFilter(input2D, request.StartRow, request.EndRow, request.StartCol, request.EndCol),
                "grayscale" => MatrixFilter.ApplyGrayscaleFilter(input2D, request.StartRow, request.EndRow, request.StartCol, request.EndCol),
                _ => throw new ArgumentException($"Unknown filter type: {request.FilterType}")
            };

            var processedJagged = ToJagged(processed2D);

            return Ok(new FilterResponse
            {
                ProcessedMatrix = processedJagged,
                FilterApplied = request.FilterType,
                ProcessedAt = DateTime.UtcNow
            });
        }
        catch (ArgumentException ex)
        {
            return BadRequest(new { error = ex.Message });
        }
        catch (Exception ex)
        {
            return StatusCode(500, new { error = "Internal server error" });
        }
    }

    [HttpPost("apply-image")]
    [Consumes("multipart/form-data")]
    [ProducesResponseType(typeof(FileResult), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    public async Task<IActionResult> ApplyFilterToImage([FromForm] IFormFile image, [FromForm] string filterType)
    {
        try
        {
            if (image == null || image.Length == 0)
            {
                return BadRequest(new { error = "Image file is required" });
            }

            if (string.IsNullOrWhiteSpace(filterType))
            {
                return BadRequest(new { error = "Filter type is required" });
            }

            var allowedExtensions = new[] { ".jpg", ".jpeg", ".png", ".bmp" };
            var extension = Path.GetExtension(image.FileName).ToLowerInvariant();
            if (!allowedExtensions.Contains(extension))
            {
                return BadRequest(new { error = "Only JPG, PNG, and BMP images are supported" });
            }

            byte[,] matrix;
            using (var stream = image.OpenReadStream())
            using (var loadedImage = await Image.LoadAsync<Rgb24>(stream))
            {
                matrix = ImageToMatrix(loadedImage);
            }

            int rows = matrix.GetLength(0);
            int cols = matrix.GetLength(1);

            byte[,] processedMatrix = filterType.ToLowerInvariant() switch
            {
                "blur" => MatrixFilter.ApplyBlurFilter(matrix, 0, rows, 0, cols),
                "sharpen" => MatrixFilter.ApplySharpenFilter(matrix, 0, rows, 0, cols),
                "edgedetection" or "edge" => MatrixFilter.ApplyEdgeDetectionFilter(matrix, 0, rows, 0, cols),
                "grayscale" => MatrixFilter.ApplyGrayscaleFilter(matrix, 0, rows, 0, cols),
                _ => throw new ArgumentException($"Unknown filter type: {filterType}")
            };

            using var resultImage = MatrixToImage(processedMatrix);
            using var outputStream = new MemoryStream();

            await resultImage.SaveAsPngAsync(outputStream);
            outputStream.Position = 0;

            return File(outputStream.ToArray(), "image/png", $"filtered_{Path.GetFileNameWithoutExtension(image.FileName)}.png");
        }
        catch (ArgumentException ex)
        {
            return BadRequest(new { error = ex.Message });
        }
        catch (Exception ex)
        {
            return StatusCode(500, new { error = "Internal server error processing image" });
        }
    }

    [HttpGet("available")]
    public ActionResult<IEnumerable<string>> GetAvailableFilters()
    {
        return Ok(new[] { "blur", "sharpen", "edgedetection", "grayscale" });
    }

    private byte[,] ImageToMatrix(Image<Rgb24> image)
    {
        int height = image.Height;
        int width = image.Width;
        byte[,] matrix = new byte[height, width];

        for (int y = 0; y < height; y++)
        {
            for (int x = 0; x < width; x++)
            {
                var pixel = image[x, y];
                matrix[y, x] = (byte)(0.299 * pixel.R + 0.587 * pixel.G + 0.114 * pixel.B);
            }
        }

        return matrix;
    }

    private Image<Rgb24> MatrixToImage(byte[,] matrix)
    {
        int height = matrix.GetLength(0);
        int width = matrix.GetLength(1);
        var image = new Image<Rgb24>(width, height);

        for (int y = 0; y < height; y++)
        {
            for (int x = 0; x < width; x++)
            {
                byte value = matrix[y, x];
                image[x, y] = new Rgb24(value, value, value);
            }
        }

        return image;
    }

    private static byte[,] JaggedTo2D(int[][] jagged)
    {
        if (jagged == null || jagged.Length == 0) return new byte[0, 0];
        int rows = jagged.Length;
        int cols = jagged[0].Length;
        var result = new byte[rows, cols];
        for (int i = 0; i < rows; i++)
        {
            if (jagged[i].Length != cols)
                throw new ArgumentException("All rows in the jagged array must have the same length", nameof(jagged));
            for (int j = 0; j < cols; j++)
            {
                int val = jagged[i][j];
                if (val < 0 || val > 255)
                    throw new ArgumentException("Matrix values must be in range 0..255", nameof(jagged));
                result[i, j] = (byte)val;
            }
        }
        return result;
    }

    private static int[][] ToJagged(byte[,] matrix)
    {
        if (matrix == null) return Array.Empty<int[]>();
        int rows = matrix.GetLength(0);
        int cols = matrix.GetLength(1);
        var jagged = new int[rows][];
        for (int i = 0; i < rows; i++)
        {
            jagged[i] = new int[cols];
            for (int j = 0; j < cols; j++)
                jagged[i][j] = matrix[i, j];
        }
        return jagged;
    }
}