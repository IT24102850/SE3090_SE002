namespace SmeBackend.DTOs;

public record RegisterRequest(string Email, string Password, string FullName, string Phone, Guid TenantId);
public record LoginRequest(string Email, string Password);
public record AuthResponse(string AccessToken, string RefreshToken, DateTime ExpiresAt, string Role, string FullName);
public record RefreshRequest(string RefreshToken);