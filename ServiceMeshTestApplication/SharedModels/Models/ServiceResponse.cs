namespace SharedModels.Models;

public class ServiceResponse
{
    public bool Success { get; set; }
    public string Message { get; set; } = string.Empty;
    public object? Data { get; set; }
    public long ExecutionTimeMs { get; set; }
    public double CpuUsagePercent { get; set; }
    public double MemoryUsageMb { get; set; }
    public string ServiceName { get; set; } = string.Empty;
    public DateTime Timestamp { get; set; } = DateTime.UtcNow;
}