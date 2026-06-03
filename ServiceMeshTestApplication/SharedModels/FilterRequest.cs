namespace SharedModels;

public class FilterRequest
{
    public required string FilterType { get; set; }
    public required byte[,] Matrix { get; set; }
    public int StartRow { get; set; } = 0;
    public int EndRow { get; set; }
    public int StartCol { get; set; } = 0;
    public int EndCol { get; set; }
}