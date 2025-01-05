unit JWTManager;

interface

uses
  System.SysUtils, System.JSON, System.DateUtils,
  JOSE.Core.JWT, JOSE.Core.Builder, JOSE.Core.JWA, JOSE.Types.JSON,
  UserModel;

type
  TJWTClaims = record
    UserId: Integer;
    Username: string;
    Role: TUserRole;
    constructor Create(AUserId: Integer; const AUsername: string; ARole: TUserRole);
  end;

  TJWTManager = class
  private
    const
      SECRET_KEY = 'your-secret-key-here';
      TOKEN_EXPIRY_HOURS = 24;
  public
    class function GenerateToken(const Claims: TJWTClaims): string;
    class function ValidateToken(const Token: string; out Claims: TJWTClaims): Boolean;
    class function GetUserIdFromToken(const Token: string): Integer;
    class function GetRoleFromToken(const Token: string): TUserRole;
  end;

implementation

{ TJWTClaims }

constructor TJWTClaims.Create(AUserId: Integer; const AUsername: string; ARole: TUserRole);
begin
  UserId := AUserId;
  Username := AUsername;
  Role := ARole;
end;

{ TJWTManager }

class function TJWTManager.GenerateToken(const Claims: TJWTClaims): string;
var
  JWT: TJWT;
begin
  JWT := TJWT.Create;
  try
    // Set standard claims
    JWT.Claims.IssuedAt := Now;
    JWT.Claims.Expiration := IncHour(Now, TOKEN_EXPIRY_HOURS);

    // Set custom claims
    JWT.Claims.JSON.AddPair('id', TJSONNumber.Create(Claims.UserId));
    JWT.Claims.JSON.AddPair('username', Claims.Username);
    JWT.Claims.JSON.AddPair('role', TJSONNumber.Create(Integer(Claims.Role))); // Explicitly cast to Integer

    // Sign and create token
    Result := TJOSE.SHA256CompactToken(SECRET_KEY, JWT);
  finally
    JWT.Free;
  end;
end;

class function TJWTManager.ValidateToken(const Token: string; out Claims: TJWTClaims): Boolean;
var
  JWT: TJWT;
  ClaimValue: TJSONValue;
  RoleValue: Integer;
begin
  Result := False;

  if Token = '' then
    Exit;

  try
    JWT := TJOSE.Verify(SECRET_KEY, Token);
    try
      // Check if token is verified and not expired
      if not (JWT.Verified and (JWT.Claims.Expiration > Now)) then
        Exit;

      // Extract and validate user ID
      ClaimValue := JWT.Claims.JSON.GetValue('id');
      if not Assigned(ClaimValue) then
        Exit;

      // Extract and validate role
      ClaimValue := JWT.Claims.JSON.GetValue('role');
      if not Assigned(ClaimValue) then
        Exit;

      RoleValue := (ClaimValue as TJSONNumber).AsInt;
      // Validate that role value is within valid range
      if not (RoleValue in [Integer(urAdmin)..Integer(urStockOfficer)]) then
        Exit;

      // Create claims object with validated data
      Claims := TJWTClaims.Create(
        (JWT.Claims.JSON.GetValue('id') as TJSONNumber).AsInt,
        JWT.Claims.JSON.GetValue('username').Value,
        TUserRole(RoleValue)
      );

      Result := True;
    finally
      JWT.Free;
    end;
  except
    Result := False;
  end;
end;

class function TJWTManager.GetUserIdFromToken(const Token: string): Integer;
var
  JWT: TJWT;
  ClaimValue: TJSONValue;
begin
  Result := 0;

  if Token = '' then
    Exit;

  try
    JWT := TJOSE.Verify(SECRET_KEY, Token);
    try
      if JWT.Verified then
      begin
        ClaimValue := JWT.Claims.JSON.GetValue('id');
        if Assigned(ClaimValue) then
          Result := (ClaimValue as TJSONNumber).AsInt;
      end;
    finally
      JWT.Free;
    end;
  except
    Result := 0;
  end;
end;

class function TJWTManager.GetRoleFromToken(const Token: string): TUserRole;
var
  JWT: TJWT;
  ClaimValue: TJSONValue;
  RoleValue: Integer;
begin
  Result := urStockOfficer; // Default to lowest privilege level

  if Token = '' then
    Exit;

  try
    JWT := TJOSE.Verify(SECRET_KEY, Token);
    try
      if JWT.Verified then
      begin
        ClaimValue := JWT.Claims.JSON.GetValue('role');
        if Assigned(ClaimValue) then
        begin
          RoleValue := (ClaimValue as TJSONNumber).AsInt;
          // Validate role value before converting
          if RoleValue in [Integer(urAdmin)..Integer(urStockOfficer)] then
            Result := TUserRole(RoleValue);
        end;
      end;
    finally
      JWT.Free;
    end;
  except
    Result := urStockOfficer;
  end;
end;

end.
