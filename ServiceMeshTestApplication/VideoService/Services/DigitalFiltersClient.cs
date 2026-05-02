namespace VideoService.Services;

public class DigitalFiltersClient
{
    private readonly HttpClient _httpClient;

    public DigitalFiltersClient(HttpClient httpClient)
    {
        _httpClient = httpClient;
    }

    public async Task<string> ApplyFilter(string filterType, int frameCount)
    {
        var response = await _httpClient.PostAsJsonAsync("/api/filters/apply", new
        {
            FilterType = filterType,
            FrameCount = frameCount
        });

        response.EnsureSuccessStatusCode();
        return await response.Content.ReadAsStringAsync();
    }

    public async Task<bool> CheckHealth()
    {
        try
        {
            var response = await _httpClient.GetAsync("/health");
            return response.IsSuccessStatusCode;
        }
        catch
        {
            return false;
        }
    }
}