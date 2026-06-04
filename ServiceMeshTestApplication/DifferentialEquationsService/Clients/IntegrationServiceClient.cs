using SharedModels.Models;
using System.Text.Json;

public class IntegrationServiceClient
{
    private readonly HttpClient _httpClient;

    public IntegrationServiceClient(HttpClient httpClient)
    {
        _httpClient = httpClient;
    }

    public async Task<string> GetAntiderivativeAsync(string expression)
    {
        var request = new AntiderivativeRequest { Expression = expression };
        var response = await _httpClient.PostAsJsonAsync("api/integration/antiderivative", request);
        response.EnsureSuccessStatusCode();

        var serviceResponse = await response.Content.ReadFromJsonAsync<ServiceResponse>();
        if (serviceResponse == null || !serviceResponse.Success)
            throw new Exception("Integration service failed: " + serviceResponse?.Message);

        // Извлекаем строку первообразной – пробуем оба варианта регистра
        var dataElement = JsonSerializer.SerializeToElement(serviceResponse.Data);
        if (dataElement.TryGetProperty("Antiderivative", out JsonElement antiderivativeProp))
            return antiderivativeProp.GetString()!;
        if (dataElement.TryGetProperty("antiderivative", out antiderivativeProp))
            return antiderivativeProp.GetString()!;

        throw new Exception("Antiderivative property not found in response");
    }

    public async Task<double> SolveEquationAsync(string expression, double initialX, double range, int steps)
    {
        var request = new IntegrationRequest { Function = expression, LowerBound = initialX, UpperBound = range, Steps = steps };
        var response = await _httpClient.PostAsJsonAsync("api/integration/calculate", request);
        response.EnsureSuccessStatusCode();

        var serviceResponse = await response.Content.ReadFromJsonAsync<ServiceResponse>();
        if (serviceResponse == null || !serviceResponse.Success)
            throw new Exception("Integration service failed: " + serviceResponse?.Message);

        // Извлекаем строку первообразной – пробуем оба варианта регистра
        var dataElement = JsonSerializer.SerializeToElement(serviceResponse.Data);
        if (dataElement.TryGetProperty("result", out JsonElement integrationProp))
            return integrationProp.GetDouble()!;
        if (dataElement.TryGetProperty("Result", out integrationProp))
            return integrationProp.GetDouble()!;

        throw new Exception("Antiderivative property not found in response");
    }
}