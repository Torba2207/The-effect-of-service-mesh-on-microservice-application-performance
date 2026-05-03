FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS base
WORKDIR /app
EXPOSE 5001
ENV ASPNETCORE_HTTP_PORTS=5001

FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src
# Copy the project files
COPY ["PermutationService/PermutationService.csproj", "PermutationService/"]
COPY ["SharedModels/SharedModels.csproj", "SharedModels/"]
# Restore dependencies
RUN dotnet restore "PermutationService/PermutationService.csproj"

# Copy the rest of the source code
COPY . .
WORKDIR "/src/PermutationService"
RUN dotnet build "PermutationService.csproj" -c Release -o /app/build

FROM build AS publish
RUN dotnet publish "PermutationService.csproj" -c Release -o /app/publish /p:UseAppHost=false

FROM base AS final
WORKDIR /app
COPY --from=publish /app/publish .
ENTRYPOINT ["dotnet", "PermutationService.dll"]
