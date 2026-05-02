using System.Diagnostics;
using System.Text.RegularExpressions;

namespace IntegrationService.Services;

public class IntegralCalculator
{
    public (double result, long execTimeMs, double cpuUsagePercent)
        CalculateIntegral(string function, double lower, double upper, int steps)
    {
        var stopwatch = Stopwatch.StartNew();
        var startCpuTime = Process.GetCurrentProcess().TotalProcessorTime;

        double h = (upper - lower) / steps;
        double sum = 0.0;

        for (int i = 0; i < steps; i++)
        {
            double x = lower + (i + 0.5) * h;
            sum += EvaluateFunction(x, function) * h;
        }

        stopwatch.Stop();
        var endCpuTime = Process.GetCurrentProcess().TotalProcessorTime;
        double cpuUsedMs = (endCpuTime - startCpuTime).TotalMilliseconds;
        double cpuPercent = stopwatch.ElapsedMilliseconds > 0
            ? (cpuUsedMs / stopwatch.ElapsedMilliseconds) * 100
            : 0;

        return (sum, stopwatch.ElapsedMilliseconds, cpuPercent);
    }

    private static double EvaluateFunction(double x, string function)
    {
        return function.ToLower() switch
        {
            "x^2" => x * x,
            "sin" => Math.Sin(x),
            "cos" => Math.Cos(x),
            "exp" => Math.Exp(x),
            "1/x" => 1.0 / (x + 1e-10),
            _ => throw new NotSupportedException($"Function '{function}' not supported")
        };
    }
    public string ComputeAntiderivative(string expression)
    {
    expression = expression.Replace(" ", "");

    var terms = new List<(string term, int sign)>();
    var matches = Regex.Matches(expression, @"([+-]?[^+-]+)");
    foreach (Match m in matches)
    {
        string term = m.Value;
        int sign = 1;
        if (term.StartsWith("-"))
        {
            sign = -1;
            term = term.Substring(1);
        }
        else if (term.StartsWith("+"))
        {
            term = term.Substring(1);
        }
        terms.Add((term, sign));
    }

    var integratedTerms = new List<string>();
    foreach (var (term, sign) in terms)
    {
        string integrated = IntegrateTerm(term);
        if (integrated == null)
            throw new Exception($"Cannot integrate term: {term}");

        string resultTerm = (sign == -1 && !integrated.StartsWith("-")) ? "-" + integrated : integrated;
        if (sign == -1 && integrated.StartsWith("-"))
            resultTerm = "+" + integrated.Substring(1);
        if (sign == 1 && integrated.StartsWith("-"))
            resultTerm = integrated;

        integratedTerms.Add(resultTerm);
    }

    string final = string.Join("", integratedTerms);
    if (final.StartsWith("+"))
        final = final.Substring(1);
    return final;
}
    private static string IntegrateTerm(string term)
    {
        if (double.TryParse(term, out double constVal))
            return $"{constVal}*x";

        var matchPower = Regex.Match(term, @"^x\^(-?\d+)$|^x\^(\d+)$|^x$");
        if (matchPower.Success)
        {
            int exponent = 1;
            if (matchPower.Groups[1].Success)
                exponent = int.Parse(matchPower.Groups[1].Value);
            else if (matchPower.Groups[2].Success)
                exponent = int.Parse(matchPower.Groups[2].Value);
            else if (term == "x")
                exponent = 1;

            int newExp = exponent + 1;
            if (newExp == 0)
                return "ln|x|";
            else
            {
                double coeff = 1.0 / newExp;
                string powerPart = PowerToMultiplication("x", newExp);
                if (Math.Abs(coeff - 1.0) < 1e-12)
                    return powerPart;
                else
                    return $"{coeff}*{powerPart}";
            }
        }

        if (term == "sin(x)") return "-cos(x)";
        if (term == "cos(x)") return "sin(x)";

        var matchConstX = Regex.Match(term, @"^(\d+)\*x$");
        if (matchConstX.Success)
        {
            double c = double.Parse(matchConstX.Groups[1].Value);
            return $"{c / 2}*x*x";
        }

        throw new Exception($"Cannot integrate term: {term}");
    }

    private static string PowerToMultiplication(string baseVar, int exponent)
    {
        if (exponent == 0) return "1";
        if (exponent == 1) return baseVar;
        return string.Join("*", Enumerable.Repeat(baseVar, exponent));
    }
}