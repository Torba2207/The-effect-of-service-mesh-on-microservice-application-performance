public class CustomMatrixFilterRequest
{
    public int[][] Matrix { get; set; } = Array.Empty<int[]>();

    public string FilterName { get; set; } = string.Empty;
    public int KernelSize { get; set; } = 3;
}