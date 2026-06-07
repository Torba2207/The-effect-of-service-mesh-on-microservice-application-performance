using System.Text.Json;

namespace DigitalFiltersService.Services;

public class AiServiceClient
{
    private readonly HttpClient _http;
    private readonly ILogger<AiServiceClient> _logger;

    public AiServiceClient(HttpClient http, ILogger<AiServiceClient> logger)
    {
        _http = http;
        _logger = logger;
        _logger.LogInformation("AiServiceClient for DigitalFilters created with base {Base}", _http.BaseAddress);
    }

    public async Task<int[][]> GenerateFilterMatrixAsync(int matrixSize, string filterName, CancellationToken ct = default)
    {
        var prompt = $"Give me a 2D integer filter matrix of size {matrixSize}x{matrixSize} for a {filterName} filter.";
        var payload = new
        {
            user_input = prompt,
            MatrixSize = matrixSize,
            FilterName = filterName
        };

        _logger.LogInformation("Calling AI service: {Url} prompt={Prompt}", new Uri(_http.BaseAddress, "api/Ai/generate"), prompt);

        try
        {
            using var resp = await _http.PostAsJsonAsync("api/Ai/generate", payload, ct);
            var responseText = await resp.Content.ReadAsStringAsync(ct);
            _logger.LogInformation("AI response (status {Status}): {Body}", resp.StatusCode, responseText);

            resp.EnsureSuccessStatusCode();

            using var doc = JsonDocument.Parse(responseText);

            if (doc.RootElement.ValueKind == JsonValueKind.Object)
            {
                var propNames = new[] { "data", "result", "matrix", "value", "filter_matrix", "result_matrix" };

                foreach (var prop in doc.RootElement.EnumerateObject())
                {
                    var name = prop.Name.Trim();
                    if (propNames.Contains(name, StringComparer.OrdinalIgnoreCase))
                    {
                        return ParseJsonElementToIntMatrix(prop.Value);
                    }
                }

                if (doc.RootElement.TryGetProperty("Data", out var dataProp))
                    return ParseJsonElementToIntMatrix(dataProp);
                if (doc.RootElement.TryGetProperty("Matrix", out var matrixProp))
                    return ParseJsonElementToIntMatrix(matrixProp);

                foreach (var prop in doc.RootElement.EnumerateObject())
                {
                    if (prop.Value.ValueKind == JsonValueKind.Object)
                    {
                        foreach (var nested in prop.Value.EnumerateObject())
                        {
                            var nestedName = nested.Name.Trim();
                            if (propNames.Contains(nestedName, StringComparer.OrdinalIgnoreCase))
                                return ParseJsonElementToIntMatrix(nested.Value);
                        }
                    }
                }

                throw new InvalidOperationException("AI response did not contain a recognized filter matrix payload.");
            }

            return ParseJsonElementToIntMatrix(doc.RootElement);
        }
        catch (HttpRequestException ex)
        {
            _logger.LogError(ex, "HttpRequestException calling AI service at {Base}: {Message}", _http.BaseAddress, ex.Message);
            throw;
        }
        catch (TaskCanceledException ex) when (!ct.IsCancellationRequested)
        {
            _logger.LogError(ex, "Timeout when calling AI service at {Base}", _http.BaseAddress);
            throw new HttpRequestException("AI service request timed out", ex);
        }
        catch (JsonException ex)
        {
            _logger.LogError(ex, "Failed to parse AI response JSON");
            throw;
        }
    }

    private static int[][] ParseJsonElementToIntMatrix(JsonElement element)
    {
        if (element.ValueKind == JsonValueKind.Array)
        {
            var matrix = new List<int[]>();
            foreach (var rowElement in element.EnumerateArray())
            {
                matrix.Add(ParseJsonElementToIntArray(rowElement));
            }
            return [.. matrix];
        }

        if (element.ValueKind == JsonValueKind.String)
        {
            var s = element.GetString()?.Trim() ?? string.Empty;

            if (s.StartsWith('[') && s.EndsWith(']'))
            {
                try
                {
                    using var innerDoc = JsonDocument.Parse(s);
                    return ParseJsonElementToIntMatrix(innerDoc.RootElement);
                }
                catch
                {
                    var rows = s.Split([']', '['], StringSplitOptions.RemoveEmptyEntries)
                                .Where(r => r.Trim() != "," && !string.IsNullOrWhiteSpace(r));

                    return [.. rows.Select(r => r.Split([','], StringSplitOptions.RemoveEmptyEntries)
                                                 .Select(v => int.Parse(v.Trim())).ToArray())];
                }
            }
        }

        throw new InvalidOperationException("Unsupported AI matrix response format.");
    }

    private static int[] ParseJsonElementToIntArray(JsonElement element)
    {
        if (element.ValueKind == JsonValueKind.Array)
        {
            var list = new List<int>();
            foreach (var el in element.EnumerateArray())
            {
                if (el.ValueKind == JsonValueKind.Number && el.TryGetInt32(out var v))
                    list.Add(v);
                else if (el.ValueKind == JsonValueKind.String && int.TryParse(el.GetString(), out var sv))
                    list.Add(sv);
                else
                    throw new InvalidOperationException("AI returned non-integer array element inside matrix.");
            }
            return [.. list];
        }

        if (element.ValueKind == JsonValueKind.String)
        {
            var s = element.GetString()?.Trim() ?? string.Empty;
            var tokens = s.Split([',', ' '], StringSplitOptions.RemoveEmptyEntries);
            return [.. tokens.Select(t => int.Parse(t.Trim()))];
        }

        throw new InvalidOperationException("Invalid row element format within matrix.");
    }
}