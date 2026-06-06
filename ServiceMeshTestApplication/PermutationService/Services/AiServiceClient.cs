using System.Text.Json;

namespace PermutationService.Services;

public class AiServiceClient
{
    private readonly HttpClient _http;
    private readonly ILogger<AiServiceClient> _logger;

    public AiServiceClient(HttpClient http, ILogger<AiServiceClient> logger)
    {
        _http = http;
        _logger = logger;
        _logger.LogInformation("AiServiceClient created with base {Base}", _http.BaseAddress);
    }

    public async Task<int[]> GenerateRandomArrayAsync(int count, int minVal, int maxVal, int seed, CancellationToken ct = default)
    {
        var prompt = $"Give me {count} integers between {minVal} and {maxVal} with seed {seed}";
        var payload = new 
        {
            user_input = prompt,
            Count = count,
            MinVal = minVal,
            MaxVal = maxVal,
            Seed = seed
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
                var propNames = new[] { "data", "result", "value", "resultarray", "result_array" };

                foreach (var prop in doc.RootElement.EnumerateObject())
                {
                    var name = prop.Name.Trim();
                    if (propNames.Contains(name, StringComparer.OrdinalIgnoreCase))
                    {
                        return ParseJsonElementToIntArray(prop.Value);
                    }
                }

                if (doc.RootElement.TryGetProperty("Data", out var dataProp))
                    return ParseJsonElementToIntArray(dataProp);
                if (doc.RootElement.TryGetProperty("Result", out var resultProp))
                    return ParseJsonElementToIntArray(resultProp);

                foreach (var prop in doc.RootElement.EnumerateObject())
                {
                    if (prop.Value.ValueKind == JsonValueKind.Object)
                    {
                        foreach (var nested in prop.Value.EnumerateObject())
                        {
                            var nestedName = nested.Name.Trim();
                            if (propNames.Contains(nestedName, StringComparer.OrdinalIgnoreCase))
                                return ParseJsonElementToIntArray(nested.Value);
                        }
                    }
                }

                throw new InvalidOperationException("AI response did not contain a recognized payload property (Data/Result).");
            }

            return ParseJsonElementToIntArray(doc.RootElement);
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
                    throw new InvalidOperationException("AI returned non-integer array element.");
            }
            return [.. list];
        }

        if (element.ValueKind == JsonValueKind.String)
        {
            var s = element.GetString() ?? string.Empty;
            s = s.Trim();

            if (s.StartsWith('{') && s.EndsWith('}'))
            {
                s = string.Concat("[", s.AsSpan(1, s.Length - 2), "]");
            }

            if (s.StartsWith('[') && s.EndsWith(']'))
            {
                var inner = s[1..^1];
                var parts = inner.Split([','], StringSplitOptions.RemoveEmptyEntries);
                return [.. parts.Select(p => int.Parse(p.Trim()))];
            }

            var tokens = s.Split([',', ' '], StringSplitOptions.RemoveEmptyEntries);
            if (tokens.Length > 0)
                return [.. tokens.Select(t => int.Parse(t.Trim()))];

            return [];
        }

        throw new InvalidOperationException("Unsupported AI response format.");
    }
}