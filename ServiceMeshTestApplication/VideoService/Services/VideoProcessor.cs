namespace VideoService.Services;

public class VideoProcessor
{
    public async Task<VideoCompressionResult> CompressVideo(Stream videoStream, string fileName)
    {
        var originalSize = videoStream.Length;

        await Task.Delay(100);

        var compressedSize = (long)(originalSize * 0.6);

        return new VideoCompressionResult
        {
            OriginalSize = originalSize,
            CompressedSize = compressedSize,
            CompressionRatio = (double)compressedSize / originalSize,
            FileName = fileName
        };
    }

    public async Task<FrameSplitResult> SplitFrames(Stream videoStream, string fileName)
    {
        var fileSize = videoStream.Length;

        await Task.Delay(150);

        var estimatedFrames = (int)(fileSize / 1024 / 30);
        if (estimatedFrames < 1) estimatedFrames = 1;

        return new FrameSplitResult
        {
            FrameCount = estimatedFrames,
            FileName = fileName,
            VideoSize = fileSize
        };
    }
}

public class VideoCompressionResult
{
    public string FileName { get; set; }
    public long OriginalSize { get; set; }
    public long CompressedSize { get; set; }
    public double CompressionRatio { get; set; }
}

public class FrameSplitResult
{
    public string FileName { get; set; }
    public int FrameCount { get; set; }
    public long VideoSize { get; set; }
}