using System.Diagnostics;

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
}