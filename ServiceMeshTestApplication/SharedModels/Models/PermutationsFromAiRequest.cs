namespace SharedModels.Models;

public class PermutationsFromAiRequest
{
    public int Count { get; set; }
    public int MinVal { get; set; } = 1;
    public int MaxVal { get; set; } = 100;
    public int Seed { get; set; } = 0;
}