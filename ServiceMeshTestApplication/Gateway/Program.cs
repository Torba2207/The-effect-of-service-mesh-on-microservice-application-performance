var builder = WebApplication.CreateBuilder(args);

builder.Services.AddReverseProxy();
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();

var app = builder.Build();

if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
}

app.Use(async (context, next) =>
{
    Console.WriteLine($"[GATEWAY] {context.Request.Method} {context.Request.Path}");
    await next();
    Console.WriteLine($"[GATEWAY] Response: {context.Response.StatusCode}");
});

app.MapReverseProxy();
app.MapGet("/health", () => Results.Ok(new { gateway = "active", mode = "static-routing" }));
app.MapGet("/info", () => Results.Ok(new
{
    name = "API Gateway",
    version = "1.0.0",
    routes = new[]
    {
        "/api/permutation -> localhost:5001",
        "/api/fibonacci -> localhost:5002",
        "/api/differential-equations -> localhost:5003",
        "/api/integration -> localhost:5004",
        "/api/ai -> localhost:5005",
        "/api/video -> localhost:5006",
        "/api/digital-filters -> localhost:5007"
    }
}));

app.Run();