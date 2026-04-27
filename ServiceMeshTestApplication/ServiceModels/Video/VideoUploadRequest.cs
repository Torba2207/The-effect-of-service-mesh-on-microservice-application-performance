namespace ServiceModels.Video;

/// <summary>
/// Video upload request metadata
/// </summary>
public class VideoUploadRequest
{
    public string FileName { get; set; } = string.Empty;
    public long FileSize { get; set; }
    public string ContentType { get; set; } = string.Empty;
    public Dictionary<string, string> Metadata { get; set; } = new();
}