namespace SharedModels.Models;

public class IntegrationRequest
{
    public string Function { get; set; } = "x^2";
    public double LowerBound { get; set; } = 0.0;
    public double UpperBound { get; set; } = 1.0;
    public int Steps { get; set; } = 1_000_000;
}