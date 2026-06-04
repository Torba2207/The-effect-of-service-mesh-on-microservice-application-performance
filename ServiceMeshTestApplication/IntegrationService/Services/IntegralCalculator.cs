using System.Diagnostics;
using System.Globalization;
using System.Text.RegularExpressions;

namespace IntegrationService.Services;

public class IntegralCalculator
{
    public (double result, long execTimeMs, double cpuUsagePercent)
        CalculateIntegral(string function, double lower, double upper, int steps)
    {
        var stopwatch = Stopwatch.StartNew();
        var startCpuTime = Process.GetCurrentProcess().TotalProcessorTime;

        double h = (upper - lower) / steps;
        double sum = 0.0;

        for (int i = 0; i < steps; i++)
        {
            double x = lower + (i + 0.5) * h;
            sum += EvaluateFunction(x, function) * h;
        }

        stopwatch.Stop();
        var endCpuTime = Process.GetCurrentProcess().TotalProcessorTime;
        double cpuUsedMs = (endCpuTime - startCpuTime).TotalMilliseconds;
        double cpuPercent = stopwatch.ElapsedMilliseconds > 0
            ? (cpuUsedMs / stopwatch.ElapsedMilliseconds) * 100
            : 0;

        return (sum, stopwatch.ElapsedMilliseconds, cpuPercent);
    }

    private static double EvaluateFunction(double x, string function)
    {
        return function.ToLower() switch
        {
            "x^2" => x * x,
            "sin" => Math.Sin(x),
            "cos" => Math.Cos(x),
            "exp" => Math.Exp(x),
            "1/x" => 1.0 / (x + 1e-10),
            _ => throw new NotSupportedException($"Function '{function}' not supported")
        };
    }
    public string ComputeAntiderivative(string expression)
    {
        expression = expression.Replace(" ", "");

        var terms = new List<(string term, int sign)>();
        var matches = Regex.Matches(expression, @"([+-]?[^+-]+)");
        foreach (Match m in matches)
        {
            string term = m.Value;
            int sign = 1;
            if (term.StartsWith("-"))
            {
                sign = -1;
                term = term.Substring(1);
            }
            else if (term.StartsWith("+"))
            {
                term = term.Substring(1);
            }
            terms.Add((term, sign));
        }

        var integratedTerms = new List<string>();
        foreach (var (term, sign) in terms)
        {
            string integrated = IntegrateTerm(term);
            if (integrated == null)
                throw new Exception($"Cannot integrate term: {term}");

            string resultTerm = (sign == -1 && !integrated.StartsWith("-")) ? "-" + integrated : integrated;
            if (sign == -1 && integrated.StartsWith("-"))
                resultTerm = "+" + integrated.Substring(1);
            else if (sign == 1 && integrated.StartsWith("-"))
                resultTerm = integrated;
            else if (sign == 1 && !integrated.StartsWith("-"))
                resultTerm = "+" + integrated;

            integratedTerms.Add(resultTerm);
        }

        string final = string.Join("", integratedTerms);
        if (final.StartsWith("+"))
            final = final.Substring(1);
        return ConvertScientificToDecimal(CompressMultiplication(final).Replace(",", "."));
    }
    private static string IntegrateTerm(string term)
    {
        if (double.TryParse(term, out double constVal))
            return $"{constVal}*x";

        var matchPower = Regex.Match(term, @"^x\^(-?\d+)$|^x\^(\d+)$|^x$");
        if (matchPower.Success)
        {
            int exponent = 1;
            if (matchPower.Groups[1].Success)
                exponent = int.Parse(matchPower.Groups[1].Value);
            else if (matchPower.Groups[2].Success)
                exponent = int.Parse(matchPower.Groups[2].Value);
            else if (term == "x")
                exponent = 1;

            int newExp = exponent + 1;
            if (newExp == 0)
                return "ln|x|";
            else
            {
                double coeff = 1.0 / newExp;
                string powerPart = PowerToMultiplication("x", newExp);
                if (Math.Abs(coeff - 1.0) < 1e-12)
                    return powerPart;
                else
                    return $"{coeff}*{powerPart}";
            }
        }

        if (term == "sin(x)") return "-cos(x)";
        if (term == "cos(x)") return "sin(x)";

        // This matches patterns like: "5*x", "2*x^2", "0.5*x^-3"
        // Regex breakdown: 
        // (?<coef>\d+(\.\d+)?) -> Captures integer or decimal coefficients
        // \*x                  -> Matches the '*x' literal
        // (\^(?<pow>-?\d+))?   -> Optionally matches the '^' and an integer power (positive or negative)
        var matchPolynomial = Regex.Match(term, @"^(?<coef>\d+(\.\d+)?)\*x(\^(?<pow>-?\d+))?$");
        if (matchPolynomial.Success)
        {
            // Extract coefficient 'c'
            double c = double.Parse(matchPolynomial.Groups["coef"].Value, CultureInfo.InvariantCulture);

            // Extract exponent 'a' (defaults to 1 if there is no explicit ^ power, like "5*x")
            string powStr = matchPolynomial.Groups["pow"].Value;
            int a = string.IsNullOrEmpty(powStr) ? 1 : int.Parse(powStr);

            // Apply power rule: \int c*x^a dx = (c / (a + 1)) * x^(a + 1)
            int newExp = a + 1;
            if (newExp == 0)
            {
                return $"{c}*ln|x|"; // Rule for c*x^-1
            }

            double newCoef = c / newExp;
            return FormatResultTerm(newCoef, newExp);
        }

        throw new Exception($"Cannot integrate term: {term}");
    }

    private static string PowerToMultiplication(string baseVar, int exponent)
    {
        if (exponent == 0) return "1";
        if (exponent == 1) return baseVar;
        return string.Join("*", Enumerable.Repeat(baseVar, exponent));
    }

    private static readonly Regex MultiplicationRegex =
        new(@"_?(?<var>[a-zA-Z])(\*(\k<var>))+_?", RegexOptions.Compiled);

    private static string CompressMultiplication(string input)
    {
        if (string.IsNullOrWhiteSpace(input)) return input;

        // Strip spaces to ensure clean matching (e.g., "x * x" becomes "x*x")
        string cleanInput = input.Replace(" ", "");

        return MultiplicationRegex.Replace(cleanInput, match =>
        {
            string variable = match.Groups["var"].Value;

            // The total number of times the variable exists is 
            // 1 (the initial one) + the number of '*' repetitions found
            int count = 1 + (match.Value.Length - 1) / 2;

            return $"{variable}^{count}";
        });
    }

    private static string FormatResultTerm(double coefficient, int exponent)
    {
        if (exponent == 0)
            return $"{coefficient}";

        string powerPart = (exponent == 1) ? "x" : $"x^{exponent}";

        if (Math.Abs(coefficient - 1.0) < 1e-12)
            return powerPart; // Avoid printing "1*x^2", just print "x^2"

        return $"{coefficient}*{powerPart}";
    }

    public static string ConvertScientificToDecimal(string equation)
    {
        if (string.IsNullOrEmpty(equation)) return equation;

        // Regex pattern to catch scientific notation:
        // (?<num>\d+(\.\d+)?[eE][+-]?\d+) -> Captures an integer or decimal, followed by E/e, followed by an optional sign and digits.
        string pattern = @"(?<num>\d+(\.\d+)?[eE][+-]?\d+)";

        return Regex.Replace(equation, pattern, match =>
        {
            // Extract the captured scientific string (e.g., "2.48015873015873E-05")
            string scientificStr = match.Groups["num"].Value;

            // Parse it safely into a real double using InvariantCulture
            if (double.TryParse(scientificStr, CultureInfo.InvariantCulture, out double value))
            {
                // Format to a flat decimal string up to 20 places
                string decimalStr = value.ToString("F20", CultureInfo.InvariantCulture);

                // Trim unnecessary trailing zeros so "0.5000..." becomes "0.5"
                if (decimalStr.Contains("."))
                {
                    decimalStr = decimalStr.TrimEnd('0').TrimEnd('.');
                }

                return string.IsNullOrEmpty(decimalStr) ? "0" : decimalStr;
            }

            // Fallback in case parsing fails
            return match.Value;
        });
    }
}