using SharedModels.Models;

public class IntegrationServiceClient
{
	private readonly HttpClient _httpClient;

	public IntegrationServiceClient(HttpClient httpClient)
	{
		_httpClient = httpClient;
	}

	public async Task<ServiceResponse> GetIntegralAsync(IntegrationRequest request)
	{
		var response = await _httpClient.PostAsJsonAsync("api/integration/calculate", request);

		if (!response.IsSuccessStatusCode)
		{
			throw new Exception($"Gateway returned error: {response.StatusCode}");
		}

		return await response.Content.ReadFromJsonAsync<ServiceResponse>();
	}
}