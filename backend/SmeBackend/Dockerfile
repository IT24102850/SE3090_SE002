# Build context must be backend/SmeBackend (Railway: set "Root Directory" to
# backend/SmeBackend in the service's Settings tab).
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src
COPY *.csproj .
RUN dotnet restore
COPY . .
RUN dotnet publish -c Release -o /app --no-restore

FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS runtime
WORKDIR /app
COPY --from=build /app .
# Railway injects $PORT at runtime; Program.cs binds Kestrel to it directly.
ENTRYPOINT ["dotnet", "SmeBackend.dll"]
