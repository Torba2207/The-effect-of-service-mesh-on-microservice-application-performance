namespace ServiceModel.Models;

public class VideoCompressionResult
{
    public required string FileName { get; set; }
    public long OriginalSize { get; set; }
    public long CompressedSize { get; set; }
    public double CompressionRatio { get; set; }
    public required string CompressedFilePath { get; set; }
    public TimeSpan OriginalDuration { get; set; }
    public double OriginalBitrate { get; set; }
    public int Width { get; set; }
    public int Height { get; set; }
}