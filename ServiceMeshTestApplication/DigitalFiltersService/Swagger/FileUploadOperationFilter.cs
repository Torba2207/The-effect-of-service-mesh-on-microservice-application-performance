using Microsoft.OpenApi.Models;
using Swashbuckle.AspNetCore.SwaggerGen;

namespace DigitalFiltersService.Swagger;

public class FileUploadOperationFilter : IOperationFilter
{
    public void Apply(OpenApiOperation operation, OperationFilterContext context)
    {
        var fileParameters = context.MethodInfo.GetParameters()
            .Where(p => p.ParameterType == typeof(IFormFile))
            .ToList();

        if (!fileParameters.Any())
            return;

        operation.RequestBody = new OpenApiRequestBody
        {
            Content = new Dictionary<string, OpenApiMediaType>
            {
                ["multipart/form-data"] = new OpenApiMediaType
                {
                    Schema = new OpenApiSchema
                    {
                        Type = "object",
                        Properties = new Dictionary<string, OpenApiSchema>(),
                        Required = new HashSet<string>()
                    }
                }
            }
        };

        var formDataSchema = operation.RequestBody.Content["multipart/form-data"].Schema;

        // Add file parameters
        foreach (var fileParam in fileParameters)
        {
            formDataSchema.Properties[fileParam.Name!] = new OpenApiSchema
            {
                Type = "string",
                Format = "binary"
            };
            formDataSchema.Required.Add(fileParam.Name!);
        }

        // Add other form parameters
        foreach (var param in context.MethodInfo.GetParameters().Where(p => p.ParameterType != typeof(IFormFile)))
        {
            formDataSchema.Properties[param.Name!] = new OpenApiSchema
            {
                Type = param.ParameterType.Name.ToLower() switch
                {
                    "string" => "string",
                    "int32" => "integer",
                    "int64" => "integer",
                    "boolean" => "boolean",
                    _ => "string"
                }
            };
        }

        // Remove parameters that are now in the request body
        operation.Parameters?.Clear();
    }
}