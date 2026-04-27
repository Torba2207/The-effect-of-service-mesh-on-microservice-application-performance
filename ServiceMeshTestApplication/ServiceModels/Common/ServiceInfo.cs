namespace ServiceModels.Common;

/// <summary>
/// Service metadata information
/// </summary>
public class ServiceInfo
{
    public string ServiceName { get; set; } = string.Empty;
    public string Version { get; set; } = string.Empty;
    public string Status { get; set; } = string.Empty;
    public DateTime Timestamp { get; set; } = DateTime.UtcNow;
}