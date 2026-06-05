FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS base
WORKDIR /app
EXPOSE 5006
ENV ASPNETCORE_HTTP_PORTS=5006

# 1. Install FFmpeg in the BASE stage so it survives into production
RUN apt-get update && apt-get install -y ffmpeg && rm -rf /var/lib/apt/lists/*

# 2. Trick the C# wrapper by linking the global binaries to the /app folder it is searching
RUN mkdir -p /app/ffmpeg && \
    ln -s /usr/bin/ffmpeg /app/ffmpeg/ffmpeg && \
    ln -s /usr/bin/ffprobe /app/ffmpeg/ffprobe && \
    ln -s /usr/bin/ffmpeg /app/ffmpeg/ffmpeg.exe && \
    ln -s /usr/bin/ffprobe /app/ffmpeg/ffprobe.exe

FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src
# Copy the project files
COPY ["VideoService/VideoService.csproj", "VideoService/"]
COPY ["SharedModels/SharedModels.csproj", "SharedModels/"]
# Restore dependencies
RUN dotnet restore "VideoService/VideoService.csproj"

# Copy the rest of the source code
COPY . .
WORKDIR "/src/VideoService"
RUN dotnet build "VideoService.csproj" -c Release -o /app/build

FROM build AS publish
RUN dotnet publish "VideoService.csproj" -c Release -o /app/publish /p:UseAppHost=false

FROM base AS final
WORKDIR /app
COPY --from=publish /app/publish .
ENTRYPOINT ["dotnet", "VideoService.dll"]