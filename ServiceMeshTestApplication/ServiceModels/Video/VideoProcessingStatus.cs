namespace ServiceModels.Video;

/// <summary>
/// Video processing status enumeration
/// </summary>
public enum VideoProcessingStatus
{
    Pending,
    Processing,
    Completed,
    Failed,
    Cancelled
}