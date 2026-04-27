namespace ServiceModel.Models;

public class FrameSplitResult
{
    public required string FileName { get; set; }
    public int FrameCount { get; set; }
    public long VideoSize { get; set; }
    public required string FramesDirectory { get; set; }
    public TimeSpan Duration { get; set; }
    public double FrameRate { get; set; }
}