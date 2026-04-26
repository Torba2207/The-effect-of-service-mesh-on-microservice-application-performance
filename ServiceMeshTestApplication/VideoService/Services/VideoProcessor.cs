using FFMpegCore;
using FFMpegCore.Enums;
using System.IO;
using System.Threading.Tasks;

namespace VideoService.Services;

public class VideoProcessor
{
    private readonly string _tempPath;

    public VideoProcessor()
    {
        _tempPath = Path.Combine(Path.GetTempPath(), "VideoService");
        Directory.CreateDirectory(_tempPath);
        
        ConfigureFFmpeg();
    }

    private void ConfigureFFmpeg()
    {
        var possiblePaths = new[]
        {
            Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "ffmpeg"),
            Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "bin", "ffmpeg"),
            Path.Combine(Directory.GetCurrentDirectory(), "ffmpeg"),
            AppDomain.CurrentDomain.BaseDirectory
        };

        foreach (var path in possiblePaths)
        {
            if (Directory.Exists(path))
            {
                var ffprobePath = Path.Combine(path, "ffprobe.exe");
                var ffmpegPath = Path.Combine(path, "ffmpeg.exe");
                
                if (File.Exists(ffprobePath) && File.Exists(ffmpegPath))
                {
                    GlobalFFOptions.Configure(options => options.BinaryFolder = path);
                    return;
                }
            }
        }

        throw new FileNotFoundException(
            "FFmpeg binaries (ffmpeg.exe and ffprobe.exe) not found. " +
            $"Please ensure they are placed in one of these locations:\n" +
            string.Join("\n", possiblePaths));
    }

    public async Task<VideoCompressionResult> CompressVideo(Stream videoStream, string fileName)
    {
        var originalSize = videoStream.Length;
        
        var inputPath = Path.Combine(_tempPath, $"input_{Guid.NewGuid()}_{fileName}");
        var outputPath = Path.Combine(_tempPath, $"compressed_{Guid.NewGuid()}_{Path.GetFileNameWithoutExtension(fileName)}.mp4");

        try
        {
            await using (var fileStream = File.Create(inputPath))
            {
                videoStream.Position = 0;
                await videoStream.CopyToAsync(fileStream);
            }

            var videoInfo = await FFProbe.AnalyseAsync(inputPath);

            var success = await FFMpegArguments
                .FromFileInput(inputPath)
                .OutputToFile(outputPath, overwrite: true, options => options
                    .WithVideoCodec(VideoCodec.LibX264)
                    .WithConstantRateFactor(28)
                    .WithVideoBitrate(1000)
                    .WithAudioCodec(AudioCodec.Aac)
                    .WithAudioBitrate(128)
                    .WithFastStart()
                    .WithSpeedPreset(Speed.Medium))
                .ProcessAsynchronously();

             if (!success)
            {
                throw new InvalidOperationException("Video compression failed");
            }

            var compressedSize = new FileInfo(outputPath).Length;

            return new VideoCompressionResult
            {
                OriginalSize = originalSize,
                CompressedSize = compressedSize,
                CompressionRatio = (double)compressedSize / originalSize,
                FileName = fileName,
                CompressedFilePath = outputPath,
                OriginalDuration = videoInfo.Duration,
                OriginalBitrate = videoInfo.Format.BitRate,
                Width = videoInfo.PrimaryVideoStream?.Width ?? 0,
                Height = videoInfo.PrimaryVideoStream?.Height ?? 0
            };
        }
        finally
        {
            if (File.Exists(inputPath))
            {
                File.Delete(inputPath);
            }
        }
    }

    public async Task<FrameSplitResult> SplitFrames(Stream videoStream, string fileName)
    {
        var fileSize = videoStream.Length;
        
        var inputPath = Path.Combine(_tempPath, $"input_{Guid.NewGuid()}_{fileName}");
        var outputDirectory = Path.Combine(_tempPath, $"frames_{Guid.NewGuid()}");
        Directory.CreateDirectory(outputDirectory);

        try
        {
            await using (var fileStream = File.Create(inputPath))
            {
                videoStream.Position = 0;
                await videoStream.CopyToAsync(fileStream);
            }

            var videoInfo = await FFProbe.AnalyseAsync(inputPath);
            var frameRate = videoInfo.PrimaryVideoStream?.FrameRate ?? 30;
            var duration = videoInfo.Duration.TotalSeconds;

            var outputPattern = Path.Combine(outputDirectory, "frame_%04d.jpg");
            
            var success = await FFMpegArguments
                .FromFileInput(inputPath)
                .OutputToFile(outputPattern, overwrite: true, options => options
                    .WithCustomArgument("-qscale:v 2"))
                .ProcessAsynchronously();

            if (!success)
            {
                throw new InvalidOperationException("Frame extraction failed");
            }

            var extractedFrames = Directory.GetFiles(outputDirectory, "*.jpg").Length;

            return new FrameSplitResult
            {
                FrameCount = extractedFrames,
                FileName = fileName,
                VideoSize = fileSize,
                FramesDirectory = outputDirectory,
                Duration = videoInfo.Duration,
                FrameRate = frameRate
            };
        }
        finally
        {
            if (File.Exists(inputPath))
            {
                File.Delete(inputPath);
            }
        }
    }
}

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

public class FrameSplitResult
{
    public required string FileName { get; set; }
    public int FrameCount { get; set; }
    public long VideoSize { get; set; }
    public required string FramesDirectory { get; set; }
    public TimeSpan Duration { get; set; }
    public double FrameRate { get; set; }
}