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

    public async Task<int[][]> GenerateFilterMatrixAsync(int matrixSize, CancellationToken ct = default)
    {
        var prompt = $@"Produce VALID JSON only. The response MUST be exactly a JSON object with a single property ""Data"" containing a 2D integer array of size {matrixSize}x{matrixSize}. DO NOT return images, filenames, markdown, code fences, explanations, or any other text. If you cannot produce the matrix, return {{""Data"":[], ""Error"":""explain why""}}.";
        var payload = new
        {
            user_input = prompt
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
                        return ParseJsonElementToIntMatrix(prop.Value, matrixSize);
                    }
                }

                if (doc.RootElement.TryGetProperty("Data", out var dataProp))
                    return ParseJsonElementToIntMatrix(dataProp, matrixSize);
                if (doc.RootElement.TryGetProperty("Matrix", out var matrixProp))
                    return ParseJsonElementToIntMatrix(matrixProp, matrixSize);

                foreach (var prop in doc.RootElement.EnumerateObject())
                {
                    if (prop.Value.ValueKind == JsonValueKind.Object)
                    {
                        foreach (var nested in prop.Value.EnumerateObject())
                        {
                            var nestedName = nested.Name.Trim();
                            if (propNames.Contains(nestedName, StringComparer.OrdinalIgnoreCase))
                                return ParseJsonElementToIntMatrix(nested.Value, matrixSize);
                        }
                    }
                }

                throw new InvalidOperationException("AI response did not contain a recognized filter matrix payload.");
            }

            return ParseJsonElementToIntMatrix(doc.RootElement, matrixSize);
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

    private static int[][] ParseJsonElementToIntMatrix(JsonElement element, int expectedSize)
    {
        if (element.ValueKind == JsonValueKind.Array)
        {
            // If array of arrays -> normal 2D
            var first = element.EnumerateArray().FirstOrDefault();
            if (first.ValueKind == JsonValueKind.Array)
            {
                var matrix = new List<int[]>();
                foreach (var rowElement in element.EnumerateArray())
                {
                    matrix.Add(ParseJsonElementToIntArray(rowElement));
                }
                return matrix.ToArray();
            }

            // If flat array of numbers -> reshape to NxN when length matches
            var flat = new List<int>();
            foreach (var item in element.EnumerateArray())
            {
                if (item.ValueKind == JsonValueKind.Number && item.TryGetInt32(out var v))
                    flat.Add(v);
                else if (item.ValueKind == JsonValueKind.String && int.TryParse(item.GetString(), out var sv))
                    flat.Add(sv);
                else
                    throw new InvalidOperationException("AI returned non-integer element in flat array.");
            }

            if (flat.Count == expectedSize * expectedSize)
            {
                var matrix = new int[expectedSize][];
                for (int i = 0; i < expectedSize; i++)
                {
                    matrix[i] = flat.Skip(i * expectedSize).Take(expectedSize).ToArray();
                }
                return matrix;
            }

            // If it's not the expected total size, but equal to expectedSize -> treat as single row
            if (flat.Count == expectedSize)
            {
                return new[] { flat.ToArray() };
            }

            throw new InvalidOperationException("AI returned a flat array with unexpected length.");
        }

        if (element.ValueKind == JsonValueKind.String)
        {
            var s = element.GetString()?.Trim() ?? string.Empty;

            if (s.StartsWith('[') && s.EndsWith(']'))
            {
                try
                {
                    using var innerDoc = JsonDocument.Parse(s);
                    return ParseJsonElementToIntMatrix(innerDoc.RootElement, expectedSize);
                }
                catch
                {
                    var rows = s.Split(new[] { ']', '[' }, StringSplitOptions.RemoveEmptyEntries)
                                .Where(r => r.Trim() != "," && !string.IsNullOrWhiteSpace(r));

                    var parsed = rows.Select(r => r.Split(new[] { ',' }, StringSplitOptions.RemoveEmptyEntries)
                                                .Select(v => int.Parse(v.Trim())).ToArray()).ToArray();
                    return parsed;
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