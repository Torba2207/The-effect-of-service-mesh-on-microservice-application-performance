namespace SharedModels.Video;

public class FrameSplitDto
{
    public string FileName { get; set; } = string.Empty;
    public int FrameCount { get; set; }
    public long VideoSize { get; set; }
    public string FramesDirectory { get; set; } = string.Empty;
    public TimeSpan Duration { get; set; }
    public double FrameRate { get; set; }
    public DateTime ProcessedAt { get; set; } = DateTime.UtcNow;
}