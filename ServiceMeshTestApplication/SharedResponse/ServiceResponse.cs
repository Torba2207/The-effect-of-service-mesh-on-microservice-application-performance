namespace SharedResponse;

public class ServiceResponse
{
    public bool IsSuccess { get; set; }
    public string Message { get; set; } = string.Empty;
    public Dictionary<string, object> Metadata { get; set; } = new();

    public static ServiceResponse Success(string message = "Success")
    {
        return new ServiceResponse
        {
            IsSuccess = true,
            Message = message
        };
    }

    public static ServiceResponse Failure(string message)
    {
        return new ServiceResponse
        {
            IsSuccess = false,
            Message = message
        };
    }
}