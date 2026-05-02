

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddControllers();
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();
builder.Services.AddScoped<DifferentialService.Services.DifferentialCalculator>();

builder.Services.AddHttpClient<IntegrationServiceClient>(client =>
{
    // Read the gateway address from config[cite: 5]
    var gatewayUrl = builder.Configuration["GatewayUrl"];
    client.BaseAddress = new Uri(gatewayUrl ?? "http://localhost:5000/api/integration");
});

var app = builder.Build();

app.UseSwagger();
app.UseSwaggerUI();
app.MapControllers();
app.Run();
