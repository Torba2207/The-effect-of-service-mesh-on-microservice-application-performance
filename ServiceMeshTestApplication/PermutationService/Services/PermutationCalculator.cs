using System.Diagnostics;

namespace PermutationService.Services;

public class PermutationCalculator
{
    public (List<List<int>> permutations, long execTimeMs, double cpuUsagePercent, double memoryUsageMb)
        GetAllPermutations(int[] set)
    {
        var stopwatch = Stopwatch.StartNew();
        var startCpuTime = Process.GetCurrentProcess().TotalProcessorTime;
        var memoryBefore = GC.GetTotalMemory(true);

        var result = new List<List<int>>();
        Permute([.. set], 0, result);

        stopwatch.Stop();
        var endCpuTime = Process.GetCurrentProcess().TotalProcessorTime;
        var cpuUsedMs = (endCpuTime - startCpuTime).TotalMilliseconds;
        var cpuPercent = stopwatch.ElapsedMilliseconds > 0
            ? (cpuUsedMs / stopwatch.ElapsedMilliseconds) * 100
            : 0;

        var memoryAfter = GC.GetTotalMemory(false);
        var memoryMb = (memoryAfter - memoryBefore) / (1024.0 * 1024);

        return (result, stopwatch.ElapsedMilliseconds, cpuPercent, memoryMb);
    }

    private static void Permute(List<int> nums, int start, List<List<int>> result)
    {
        if (start == nums.Count - 1)
        {
            result.Add([.. nums]);
            return;
        }

        for (int i = start; i < nums.Count; i++)
        {
            Swap(nums, start, i);
            Permute(nums, start + 1, result);
            Swap(nums, start, i);
        }
    }

    private static void Swap(List<int> nums, int i, int j)
    {
        (nums[i], nums[j]) = (nums[j], nums[i]);
    }
}