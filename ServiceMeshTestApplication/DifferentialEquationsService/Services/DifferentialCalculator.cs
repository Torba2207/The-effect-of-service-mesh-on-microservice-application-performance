using Microsoft.Extensions.Logging;
using SharedModels.Models;
using System.Data;
using System.Globalization;
using System.Text.RegularExpressions;
using System.Threading.Tasks;

namespace DifferentialService.Services;

public class DifferentialCalculator
{
    private readonly IntegrationServiceClient _integrationClient;

    public DifferentialCalculator(IntegrationServiceClient integrationClient)
    {
        _integrationClient = integrationClient;
    }

    private async Task<string> SolveEquation(DifferentialRequest request)
    {
        string antiderivative = "";
        if (!request.Function.Contains("y", StringComparison.OrdinalIgnoreCase))
        {
            antiderivative = await _integrationClient.GetAntiderivativeAsync(request.Function);
        }
        else
        {
            string currentY = request.InitialConditionY.ToString();
            string modifiedFunc = request.Function.Replace("y", request.InitialConditionY.ToString());
            string currentEquation = request.Function;
            for (int i = 0; i < request.Steps; i++)
            {
                string integrand = (i == 0 ? modifiedFunc : $"{modifiedFunc}+{currentY}");

                antiderivative = await _integrationClient.GetAntiderivativeAsync(integrand);

                currentY = antiderivative;
            }
            antiderivative =  $"{request.InitialConditionY}+{currentY}";
        }

        if (request.InitialConditionX == request.Range)
            return antiderivative;
        return (
                EvaluateExpression(antiderivative, request.Range)
                - EvaluateExpression(antiderivative, request.InitialConditionX)
               ).ToString();
    }

    public async Task<string> SolveAsync(DifferentialRequest request)
    {
            return await SolveEquation(request);
        //return await SolveAntiderivative(request.Function);
    }

    private static double EvaluateExpression(string expression, double x)
    {
        string expr = expression.Replace("x", x.ToString(CultureInfo.InvariantCulture));

        // Regex matches: a number (integer or decimal), followed by '^', followed by an optional negative sign and digits
        string powerPattern = @"(?<base>\d+(\.\d+)?)\^(?<pow>-?\d+)";

        while (Regex.IsMatch(expr, powerPattern))
        {
            expr = Regex.Replace(expr, powerPattern, match =>
            {
                double numBase = double.Parse(match.Groups["base"].Value, CultureInfo.InvariantCulture);
                double numPow = double.Parse(match.Groups["pow"].Value, CultureInfo.InvariantCulture);

                // Calculate the actual power numerically
                double powerResult = Math.Pow(numBase, numPow);

                // Return it as a plain decimal string for the DataTable to read
                return powerResult.ToString("F15", CultureInfo.InvariantCulture);
            });
        }

        var table = new DataTable();
        var result = table.Compute(expr, null);
        return Convert.ToDouble(result);
    }
}