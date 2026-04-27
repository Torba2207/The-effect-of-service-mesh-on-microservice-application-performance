namespace ServiceModels.Video;

/// <summary>
/// Video file metadata information
/// </summary>
public class VideoMetadata
{
    public string FileName { get; set; } = string.Empty;
    public long FileSize { get; set; }
    public TimeSpan Duration { get; set; }
    public int Width { get; set; }
    public int Height { get; set; }
    public double FrameRate { get; set; }
    public long Bitrate { get; set; }
    public string Codec { get; set; } = string.Empty;
    public string Format { get; set; } = string.Empty;
}