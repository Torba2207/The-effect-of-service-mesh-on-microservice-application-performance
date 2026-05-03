FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS base
WORKDIR /app
EXPOSE 5002
ENV ASPNETCORE_HTTP_PORTS=5002

FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src
# Copy the project files
COPY ["FibonacciService/FibonacciService.csproj", "FibonacciService/"]
COPY ["SharedModels/SharedModels.csproj", "SharedModels/"]
# Restore dependencies
RUN dotnet restore "FibonacciService/FibonacciService.csproj"

# Copy the rest of the source code
COPY . .
WORKDIR "/src/FibonacciService"
RUN dotnet build "FibonacciService.csproj" -c Release -o /app/build

FROM build AS publish
RUN dotnet publish "FibonacciService.csproj" -c Release -o /app/publish /p:UseAppHost=false

FROM base AS final
WORKDIR /app
COPY --from=publish /app/publish .
ENTRYPOINT ["dotnet", "FibonacciService.dll"]
