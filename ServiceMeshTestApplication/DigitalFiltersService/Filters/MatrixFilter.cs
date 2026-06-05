namespace DigitalFiltersService.Filters;

public class MatrixFilter
{
    public static byte[,] ApplyBlurFilter(byte[,] matrix, int startRow, int endRow, int startCol, int endCol)
    {
        double[,] kernel = {
            { 1.0/16, 2.0/16, 1.0/16 },
            { 2.0/16, 4.0/16, 2.0/16 },
            { 1.0/16, 2.0/16, 1.0/16 }
        };

        return ApplyConvolution(matrix, kernel, startRow, endRow, startCol, endCol);
    }

    public static byte[,] ApplySharpenFilter(byte[,] matrix, int startRow, int endRow, int startCol, int endCol)
    {
        double[,] kernel = {
            {  0, -1,  0 },
            { -1,  5, -1 },
            {  0, -1,  0 }
        };

        return ApplyConvolution(matrix, kernel, startRow, endRow, startCol, endCol);
    }

    public static byte[,] ApplyEdgeDetectionFilter(byte[,] matrix, int startRow, int endRow, int startCol, int endCol)
    {
        double[,] kernel = {
            { -1, -1, -1 },
            { -1,  8, -1 },
            { -1, -1, -1 }
        };

        return ApplyConvolution(matrix, kernel, startRow, endRow, startCol, endCol);
    }

    public static byte[,] ApplyGrayscaleFilter(byte[,] matrix, int startRow, int endRow, int startCol, int endCol)
    {
        int rows = matrix.GetLength(0);
        int cols = matrix.GetLength(1);
        byte[,] result = new byte[rows, cols];

        Array.Copy(matrix, result, matrix.Length);

        for (int i = Math.Max(0, startRow); i < Math.Min(rows, endRow); i++)
        {
            for (int j = Math.Max(0, startCol); j < Math.Min(cols, endCol); j++)
            {
                result[i, j] = matrix[i, j];
            }
        }

        return result;
    }

    private static byte[,] ApplyConvolution(byte[,] matrix, double[,] kernel, int startRow, int endRow, int startCol, int endCol)
    {
        int rows = matrix.GetLength(0);
        int cols = matrix.GetLength(1);
        int kernelSize = kernel.GetLength(0);
        int kernelOffset = kernelSize / 2;

        double fullKernelSum = 0;
        for (int ki = 0; ki < kernelSize; ki++)
            for (int kj = 0; kj < kernelSize; kj++)
                fullKernelSum += kernel[ki, kj];

        byte[,] result = new byte[rows, cols];
        Array.Copy(matrix, result, matrix.Length);

        startRow = Math.Max(0, startRow);
        endRow = Math.Min(rows, endRow);
        startCol = Math.Max(0, startCol);
        endCol = Math.Min(cols, endCol);

        for (int i = startRow; i < endRow; i++)
        {
            for (int j = startCol; j < endCol; j++)
            {
                double sum = 0;
                double weightSum = 0;

                for (int ki = 0; ki < kernelSize; ki++)
                {
                    for (int kj = 0; kj < kernelSize; kj++)
                    {
                        int row = i + ki - kernelOffset;
                        int col = j + kj - kernelOffset;

                        if (row >= 0 && row < rows && col >= 0 && col < cols)
                        {
                            double w = kernel[ki, kj];
                            sum += matrix[row, col] * w;
                            weightSum += w;
                        }
                    }
                }

                double value;
                if (Math.Abs(fullKernelSum) > 1e-12)
                {
                    if (Math.Abs(weightSum) > 1e-12)
                        value = sum * (fullKernelSum / weightSum);
                    else
                        value = matrix[i, j];
                }
                else
                {
                    value = sum;
                }
                result[i, j] = (byte)Math.Clamp((int)Math.Round(value), 0, 255);
            }
        }

        return result;
    }
}