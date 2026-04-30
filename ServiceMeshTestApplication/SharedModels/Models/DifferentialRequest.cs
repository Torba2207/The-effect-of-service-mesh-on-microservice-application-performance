namespace SharedModels.Models;

public class DifferentialRequest
{
    public string Function { get; set; } = "x^2";
    public double InitialConditionX { get; set; } = 0.0;
    public double InitialConditionY { get; set; } = 0.0;
    public double Range { get; set; } = 1.0;
    public int Steps { get; set; } = 5;
}