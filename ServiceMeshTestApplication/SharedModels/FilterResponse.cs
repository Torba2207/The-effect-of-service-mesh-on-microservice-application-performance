namespace SharedModels;
public class FilterResponse
{
    public required byte[,] ProcessedMatrix { get; set; }
    public required string FilterApplied { get; set; }
    public DateTime ProcessedAt { get; set; } = DateTime.UtcNow;
}