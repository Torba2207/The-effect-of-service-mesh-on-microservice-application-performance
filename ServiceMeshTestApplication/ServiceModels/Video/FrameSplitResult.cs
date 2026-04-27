namespace ServiceModels.Video;

/// <summary>
/// Result of frame extraction operation
/// </summary>
public class FrameSplitResult
{
    public string FileName { get; set; } = string.Empty;
    public int FrameCount { get; set; }
    public long VideoSize { get; set; }
    public string FramesDirectory { get; set; } = string.Empty;
    public TimeSpan Duration { get; set; }
    public double FrameRate { get; set; }
    public DateTime ProcessedAt { get; set; } = DateTime.UtcNow;
    public string ProcessingId { get; set; } = Guid.NewGuid().ToString();
}