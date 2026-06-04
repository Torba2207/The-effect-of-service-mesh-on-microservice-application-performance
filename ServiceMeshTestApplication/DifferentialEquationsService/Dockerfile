FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS base
WORKDIR /app
EXPOSE 5003
ENV ASPNETCORE_HTTP_PORTS=5003


FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src
# Copy the project files
COPY ["DifferentialEquationsService/DifferentialEquationsService.csproj", "DifferentialEquationsService/"]
COPY ["SharedModels/SharedModels.csproj", "SharedModels/"]
# Restore dependencies
RUN dotnet restore "DifferentialEquationsService/DifferentialEquationsService.csproj"

# Copy the rest of the source code
COPY . .
WORKDIR "/src/DifferentialEquationsService"
RUN dotnet build "DifferentialEquationsService.csproj" -c Release -o /app/build

FROM build AS publish
RUN dotnet publish "DifferentialEquationsService.csproj" -c Release -o /app/publish /p:UseAppHost=false

FROM base AS final
WORKDIR /app
COPY --from=publish /app/publish .
ENTRYPOINT ["dotnet", "DifferentialEquationsService.dll"]