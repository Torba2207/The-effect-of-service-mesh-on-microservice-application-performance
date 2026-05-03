FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS base
WORKDIR /app
EXPOSE 5004
ENV ASPNETCORE_HTTP_PORTS=5004

FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src
# Copy the project files
COPY ["IntegrationService/IntegrationService.csproj", "IntegrationService/"]
COPY ["SharedModels/SharedModels.csproj", "SharedModels/"]
# Restore dependencies
RUN dotnet restore "IntegrationService/IntegrationService.csproj"

# Copy the rest of the source code
COPY . .
WORKDIR "/src/IntegrationService"
RUN dotnet build "IntegrationService.csproj" -c Release -o /app/build

FROM build AS publish
RUN dotnet publish "IntegrationService.csproj" -c Release -o /app/publish /p:UseAppHost=false

FROM base AS final
WORKDIR /app
COPY --from=publish /app/publish .
ENTRYPOINT ["dotnet", "IntegrationService.dll"]
