using PermutationService.Services;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddControllers();
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();
builder.Services.AddScoped<PermutationCalculator>();

var aiBase = builder.Configuration.GetValue<string>("AiService:BaseUrl")
             ?? Environment.GetEnvironmentVariable("AI_SERVICE_BASEURL")
             ?? "http://localhost:5005/";

builder.Services.AddHttpClient<AiServiceClient>(client =>
{
    client.BaseAddress = new Uri(aiBase.TrimEnd('/') + "/");
});

var app = builder.Build();

if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
}

app.UseHttpsRedirection();

app.UseAuthorization();

app.MapControllers();

app.Run();