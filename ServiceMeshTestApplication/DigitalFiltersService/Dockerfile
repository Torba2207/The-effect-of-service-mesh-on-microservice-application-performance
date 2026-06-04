FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS base
WORKDIR /app
EXPOSE 5007
ENV ASPNETCORE_HTTP_PORTS=5007

FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src
# Copy the project files
COPY ["DigitalFiltersService/DigitalFiltersService.csproj", "DigitalFiltersService/"]
COPY ["SharedModels/SharedModels.csproj", "SharedModels/"]
# Restore dependencies
RUN dotnet restore "DigitalFiltersService/DigitalFiltersService.csproj"

# Copy the rest of the source code
COPY . .
WORKDIR "/src/DigitalFiltersService"
RUN dotnet build "DigitalFiltersService.csproj" -c Release -o /app/build

FROM build AS publish
RUN dotnet publish "DigitalFiltersService.csproj" -c Release -o /app/publish /p:UseAppHost=false

FROM base AS final
WORKDIR /app
COPY --from=publish /app/publish .
ENTRYPOINT ["dotnet", "DigitalFiltersService.dll"]
