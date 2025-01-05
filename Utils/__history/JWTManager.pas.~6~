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
      SECRET_KEY = 'your-secret-key-here'; // In production, this should be stored securely
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
    JWT.Claims.JSON.AddPair('uid', TJSONNumber.Create(Claims.UserId));
    JWT.Claims.JSON.AddPair('username', Claims.Username);
    JWT.Claims.JSON.AddPair('role', TJSONNumber.Create(Ord(Claims.Role)));

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
begin
  Result := False;
  if Token = '' then
    Exit;

  try
    JWT := TJOSE.Verify(SECRET_KEY, Token);
    try
      if not (JWT.Verified and (JWT.Claims.Expiration > Now)) then
        Exit;

      // Extract claims
      ClaimValue := JWT.Claims.JSON.GetValue('uid');
      if not Assigned(ClaimValue) then
        Exit;

      Claims := TJWTClaims.Create(
        (ClaimValue as TJSONNumber).AsInt,
        JWT.Claims.JSON.GetValue('username').Value,
        TUserRole((JWT.Claims.JSON.GetValue('role') as TJSONNumber).AsInt)
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
        ClaimValue := JWT.Claims.JSON.GetValue('uid');
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
          Result := TUserRole((ClaimValue as TJSONNumber).AsInt);
      end;
    finally
      JWT.Free;
    end;
  except
    Result := urStockOfficer;
  end;
end;

end.
