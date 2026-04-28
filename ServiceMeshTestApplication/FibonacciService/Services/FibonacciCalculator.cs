using System.Diagnostics;
using System.Numerics;

namespace FibonacciService.Services;

public class FibonacciCalculator
{
    public (BigInteger result, long execTimeMs, double cpuUsagePercent)
        CalculateFibonacci(int n)
    {
        var stopwatch = Stopwatch.StartNew();
        var startCpuTime = Process.GetCurrentProcess().TotalProcessorTime;

        BigInteger result = Compute(n);

        stopwatch.Stop();
        var endCpuTime = Process.GetCurrentProcess().TotalProcessorTime;
        var cpuUsedMs = (endCpuTime - startCpuTime).TotalMilliseconds;
        var cpuPercent = stopwatch.ElapsedMilliseconds > 0
            ? (cpuUsedMs / stopwatch.ElapsedMilliseconds) * 100
            : 0;

        return (result, stopwatch.ElapsedMilliseconds, cpuPercent);
    }

    private static BigInteger Compute(int n)
    {
        if (n <= 1) return n;

        BigInteger a = 0, b = 1;
        for (int i = 2; i <= n; i++)
        {
            var temp = a + b;
            a = b;
            b = temp;
        }
        return b;
    }
}