using System.Globalization;
using System.Data;
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
        if (!request.Function.Contains("y", StringComparison.OrdinalIgnoreCase))
        {
            string antiderivative = await _integrationClient.GetAntiderivativeAsync(request.Function);

            double integral = EvaluateExpression(antiderivative, request.Range)
                            - EvaluateExpression(antiderivative, request.InitialConditionX);

            double result = request.InitialConditionY + integral;
            return result.ToString(CultureInfo.InvariantCulture);
        }

        double currentY = request.InitialConditionY;
        for (int i = 0; i < request.Steps; i++)
        {
            string integrand = request.Function.Replace("y", currentY.ToString(CultureInfo.InvariantCulture));

            string antiderivative = await _integrationClient.GetAntiderivativeAsync(integrand);

            double integral = EvaluateExpression(antiderivative, request.Range)
                            - EvaluateExpression(antiderivative, request.InitialConditionX);

            currentY += integral;
        }
        return currentY.ToString(CultureInfo.InvariantCulture);
    }

    private static double EvaluateExpression(string expression, double x)
    {
        string expr = expression.Replace("x", x.ToString(CultureInfo.InvariantCulture));
        var table = new DataTable();
        var result = table.Compute(expr, null);
        return Convert.ToDouble(result);
    }
}