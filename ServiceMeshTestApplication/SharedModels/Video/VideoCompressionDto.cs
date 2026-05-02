namespace SharedModels.Video;

public class VideoCompressionDto
{
    public string FileName { get; set; } = string.Empty;
    public long OriginalSize { get; set; }
    public long CompressedSize { get; set; }
    public double CompressionRatio { get; set; }
    public string CompressedFilePath { get; set; } = string.Empty;
    public TimeSpan OriginalDuration { get; set; }
    public double OriginalBitrate { get; set; }
    public int Width { get; set; }
    public int Height { get; set; }
    public DateTime ProcessedAt { get; set; } = DateTime.UtcNow;
}