using SharedModels.Models;

namespace DifferentialService.Services;

public class DifferentialCalculator
{
    private readonly IntegrationServiceClient _integrationClient;

    public DifferentialCalculator(IntegrationServiceClient integrationClient)
    {
        _integrationClient = integrationClient;
    }

    public async Task<string> SolveAsync(DifferentialRequest request)
    {
        // Case: Non-iterative (Direct Integration)
        // If the function doesn't contain 'y', we don't need Picard iterations.
        if (!request.Function.Contains("y", StringComparison.OrdinalIgnoreCase))
        {
            var integrationReq = new IntegrationRequest
            {
                Function = request.Function, // e.g., "x^2"
                LowerBound = request.InitialConditionX,
                UpperBound = request.Range,
                Steps = 1_000_000
            };

            string result = _integrationClient.GetIntegralAsync(integrationReq).Result.Data.ToString();
            return (request.InitialConditionY + result).ToString();
        }

        // Case: Iterative (Picard Method)
        string currentY = request.InitialConditionY.ToString();
        for (int i = 0; i < request.Steps; i++)
        {
            string integrand = request.Function.Replace("y", $"({currentY})");

            var integrationReq = new IntegrationRequest
            {
                Function = integrand,
                LowerBound = request.InitialConditionX,
                UpperBound = request.Range,
                Steps = 10_000
            };

            string result = _integrationClient.GetIntegralAsync(integrationReq).Result.Data.ToString();
            currentY = $"{request.InitialConditionY} + {result}";
        }

        return currentY;
    }
}
