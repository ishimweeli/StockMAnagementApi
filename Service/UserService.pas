unit UserService;

interface

uses
  System.SysUtils, System.Classes, System.Hash, System.JSON,
  System.DateUtils, JOSE.Core.JWT, JOSE.Core.Builder,
  UserModel, DatabaseModule,
  FireDAC.Comp.Client, FireDAC.Stan.Param;

type
  TAuthResponse = record
    Success: Boolean;
    Token: string;
    User: TUser;
    ErrorMessage: string;
  end;

  TJWTClaims = record
    UserId: Integer;
    Username: string;
    Role: UserModel.TUserRole;
    constructor Create(AUserId: Integer; const AUsername: string; ARole: UserModel.TUserRole);
  end;

  TJWTManager = class
  private
    const
      SECRET_KEY = 'your-secret-key-here';
      TOKEN_EXPIRY_HOURS = 24;
  public
    class function GenerateToken(const Claims: TJWTClaims): string;
    class function ValidateToken(const Token: string): Boolean;
    class function GetUserIdFromToken(const Token: string): Integer;
    class function GetRoleFromToken(const Token: string): UserModel.TUserRole;
  end;

  TAuthService = class
  public
    function Register(const Username, Password, Email: string; Role: TUserRole): TAuthResponse;
    function Login(const Username, Password: string): TAuthResponse;
    function GetUserProfile(const UserId: Integer): TUser;
    function UpdateUserProfile(const UserId: Integer; const Email, Username: string): Boolean;
    function ChangePassword(const UserId: Integer; const CurrentPassword, NewPassword: string): Boolean;
    function DeleteUser(const UserId: Integer): Boolean;
    function ValidateToken(const Token: string): Boolean;
    function ToJsonResponse(const Response: TAuthResponse): string;
  private
    function HashPassword(const Password: string): string;
    function ValidateCredentials(const Username, Password: string): Boolean;
    function UserExists(const Username, Email: string): Boolean;
    function ValidateInput(const Username, Password, Email: string): Boolean;
    function GenerateAuthToken(const User: TUser): string;
  end;

implementation

{ TJWTClaims }

constructor TJWTClaims.Create(AUserId: Integer; const AUsername: string; ARole: UserModel.TUserRole);
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
    JWT.Claims.IssuedAt := Now;
    JWT.Claims.Expiration := IncHour(Now, TOKEN_EXPIRY_HOURS);
    JWT.Claims.Subject := IntToStr(Claims.UserId);
    JWT.Claims.JSON.AddPair('username', Claims.Username);
    JWT.Claims.JSON.AddPair('role', TJSONNumber.Create(Ord(Claims.Role)));

    Result := TJOSE.SHA256CompactToken(SECRET_KEY, JWT);
  finally
    JWT.Free;
  end;
end;

class function TJWTManager.ValidateToken(const Token: string): Boolean;
var
  JWT: TJWT;
begin
  Result := False;
  if Token = '' then
    Exit;

  try
    JWT := TJOSE.Verify(SECRET_KEY, Token);
    try
      Result := JWT.Verified and (JWT.Claims.Expiration > Now);
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
begin
  Result := 0;
  if not ValidateToken(Token) then
    Exit;

  JWT := TJOSE.Verify(SECRET_KEY, Token);
  try
    Result := StrToIntDef(JWT.Claims.Subject, 0);
  finally
    JWT.Free;
  end;
end;

class function TJWTManager.GetRoleFromToken(const Token: string): UserModel.TUserRole;
var
  JWT: TJWT;
  RoleValue: TJSONValue;
begin
  Result := UserModel.TUserRole.urAdmin; // Default role
  if not ValidateToken(Token) then
    Exit;

  JWT := TJOSE.Verify(SECRET_KEY, Token);
  try
    RoleValue := JWT.Claims.JSON.GetValue('role');
    if Assigned(RoleValue) then
      Result := UserModel.TUserRole(TJSONNumber(RoleValue).AsInt);
  finally
    JWT.Free;
  end;
end;

{ TAuthService }

function TAuthService.HashPassword(const Password: string): string;
begin
  Result := THashSHA2.GetHashString(Password, SHA256);
end;

function TAuthService.ValidateInput(const Username, Password, Email: string): Boolean;
begin
  Result := (Length(Username) >= 3) and (Length(Password) >= 6) and
            (Pos('@', Email) > 1) and (Pos('.', Email) > Pos('@', Email) + 1);
end;

function TAuthService.UserExists(const Username, Email: string): Boolean;
var
  Query: TFDQuery;
begin
  Result := False;
  if (Username = '') and (Email = '') then
    Exit;

  Query := DatabaseModule1.CreateQuery;
  try
    Query.SQL.Text := 'SELECT 1 FROM users WHERE username = :username OR email = :email';
    Query.ParamByName('username').AsString := Username;
    Query.ParamByName('email').AsString := Email;
    Query.Open;
    Result := not Query.IsEmpty;
  finally
    Query.Free;
  end;
end;

function TAuthService.ValidateCredentials(const Username, Password: string): Boolean;
var
  Query: TFDQuery;
  StoredHash: string;
begin
  Result := False;
  if (Username = '') or (Password = '') then
    Exit;

  Query := DatabaseModule1.CreateQuery;
  try
    Query.SQL.Text := 'SELECT password FROM users WHERE username = :username';
    Query.ParamByName('username').AsString := Username;
    Query.Open;

    if not Query.IsEmpty then
    begin
      StoredHash := Query.FieldByName('password').AsString;
      Result := StoredHash = HashPassword(Password);
    end;
  finally
    Query.Free;
  end;
end;

function TAuthService.GenerateAuthToken(const User: TUser): string;
var
  Claims: TJWTClaims;
begin
  Claims := TJWTClaims.Create(User.Id, User.Username, User.Role);
  Result := TJWTManager.GenerateToken(Claims);
end;

function TAuthService.Register(const Username, Password, Email: string;
  Role: UserModel.TUserRole): TAuthResponse;
var
  Query: TFDQuery;
begin
  Result.Success := False;
  Result.User := nil;
  Result.Token := '';
  Result.ErrorMessage := '';

  if not ValidateInput(Username, Password, Email) then
  begin
    Result.ErrorMessage := 'Invalid input data';
    Exit;
  end;

  if not (Role in [UserModel.TUserRole.urAdmin, UserModel.TUserRole.urStockOfficer]) then
  begin
    Result.ErrorMessage := 'Invalid role specified';
    Exit;
  end;

  if UserExists(Username, Email) then
  begin
    Result.ErrorMessage := 'Username or email already exists';
    Exit;
  end;

  DatabaseModule1.StartTransaction;
  Query := DatabaseModule1.CreateQuery;
  try
    try
      Query.SQL.Text :=
        'INSERT INTO users (username, password, email, role, created_at) ' +
        'VALUES (:username, :password, :email, :role, :created_at)';

      Query.ParamByName('username').AsString := Username;
      Query.ParamByName('password').AsString := HashPassword(Password);
      Query.ParamByName('email').AsString := Email;
      Query.ParamByName('role').AsInteger := Ord(Role);
      Query.ParamByName('created_at').AsDateTime := Now;
      Query.ExecSQL;

      Result.User := TUser.Create;
      Result.User.Id := DatabaseModule1.GetConnection.GetLastAutoGenValue('users');
      Result.User.Username := Username;
      Result.User.Email := Email;
      Result.User.Role := Role;
      Result.Token := GenerateAuthToken(Result.User);
      Result.Success := True;

      DatabaseModule1.Commit;
    except
      on E: Exception do
      begin
        DatabaseModule1.Rollback;
        FreeAndNil(Result.User);
        Result.Success := False;
        Result.ErrorMessage := 'Registration failed: ' + E.Message;
      end;
    end;
  finally
    Query.Free;
  end;
end;

function TAuthService.Login(const Username, Password: string): TAuthResponse;
var
  Query: TFDQuery;
begin
  Result.Success := False;
  Result.User := nil;
  Result.Token := '';
  Result.ErrorMessage := '';

  if not ValidateCredentials(Username, Password) then
  begin
    Result.ErrorMessage := 'Invalid credentials';
    Exit;
  end;

  Query := DatabaseModule1.CreateQuery;
  try
    try
      Query.SQL.Text := 'SELECT * FROM users WHERE username = :username';
      Query.ParamByName('username').AsString := Username;
      Query.Open;

      if Query.IsEmpty then
      begin
        Result.ErrorMessage := 'User not found';
        Exit;
      end;

      Result.User := TUser.Create;
      try
        Result.User.Id := Query.FieldByName('id').AsInteger;
        Result.User.Username := Query.FieldByName('username').AsString;
        Result.User.Email := Query.FieldByName('email').AsString;
        Result.User.Role := TUserRole(Query.FieldByName('role').AsInteger);

        Result.Token := GenerateAuthToken(Result.User);
        Result.Success := True;
      except
        on E: Exception do
        begin
          FreeAndNil(Result.User);
          raise;
        end;
      end;
    except
      on E: Exception do
      begin
        Result.Success := False;
        Result.ErrorMessage := 'Login failed: ' + E.Message;
        FreeAndNil(Result.User);
      end;
    end;
  finally
    Query.Free;
  end;
end;

function TAuthService.GetUserProfile(const UserId: Integer): TUser;
var
  Query: TFDQuery;
begin
  Result := nil;
  if UserId <= 0 then
    Exit;

  Query := DatabaseModule1.CreateQuery;
  try
    Query.SQL.Text := 'SELECT * FROM users WHERE id = :id';
    Query.ParamByName('id').AsInteger := UserId;
    Query.Open;

    if not Query.IsEmpty then
    begin
      Result := TUser.Create;
      Result.Id := Query.FieldByName('id').AsInteger;
      Result.Username := Query.FieldByName('username').AsString;
      Result.Email := Query.FieldByName('email').AsString;
      Result.Role := UserModel.TUserRole(Query.FieldByName('role').AsInteger);
    end;
  finally
    Query.Free;
  end;
end;

function TAuthService.UpdateUserProfile(const UserId: Integer; const Email, Username: string): Boolean;
var
  Query: TFDQuery;
  UpdateFields: TStringList;
begin
  Result := False;
  if (UserId <= 0) or ((Email = '') and (Username = '')) then
    Exit;

  Query := DatabaseModule1.CreateQuery;
  try
    Query.SQL.Text := 'SELECT 1 FROM users WHERE (username = :username OR email = :email) AND id <> :id';
    Query.ParamByName('username').AsString := Username;
    Query.ParamByName('email').AsString := Email;
    Query.ParamByName('id').AsInteger := UserId;
    Query.Open;

    if not Query.IsEmpty then
      Exit;

    UpdateFields := TStringList.Create;
    try
      if Email <> '' then
        UpdateFields.Add('email = :email');
      if Username <> '' then
        UpdateFields.Add('username = :username');

      Query.SQL.Text := Format(
        'UPDATE users SET %s WHERE id = :id',
        [UpdateFields.CommaText]
      );

      if Email <> '' then
        Query.ParamByName('email').AsString := Email;
      if Username <> '' then
        Query.ParamByName('username').AsString := Username;

      Query.ParamByName('id').AsInteger := UserId;

      DatabaseModule1.StartTransaction;
      try
        Query.ExecSQL;
        Result := Query.RowsAffected > 0;
        DatabaseModule1.Commit;
      except
        DatabaseModule1.Rollback;
        raise;
      end;
    finally
      UpdateFields.Free;
    end;
  finally
    Query.Free;
  end;
end;

function TAuthService.ChangePassword(const UserId: Integer; const CurrentPassword,
  NewPassword: string): Boolean;
var
  Query: TFDQuery;
  StoredHash: string;
begin
  Result := False;
  if (UserId <= 0) or (CurrentPassword = '') or (NewPassword = '') then
    Exit;

  if Length(NewPassword) < 6 then
    Exit;

  Query := DatabaseModule1.CreateQuery;
  try
    Query.SQL.Text := 'SELECT password FROM users WHERE id = :id';
    Query.ParamByName('id').AsInteger := UserId;
    Query.Open;

    if Query.IsEmpty then
      Exit;

    StoredHash := Query.FieldByName('password').AsString;
    if StoredHash <> HashPassword(CurrentPassword) then
      Exit;

    Query.SQL.Text := 'UPDATE users SET password = :password WHERE id = :id';
    Query.ParamByName('password').AsString := HashPassword(NewPassword);
    Query.ParamByName('id').AsInteger := UserId;

    DatabaseModule1.StartTransaction;
    try
      Query.ExecSQL;
      Result := Query.RowsAffected > 0;
      DatabaseModule1.Commit;
    except
      DatabaseModule1.Rollback;
      raise;
    end;
  finally
    Query.Free;
  end;
end;

function TAuthService.DeleteUser(const UserId: Integer): Boolean;
var
  Query: TFDQuery;
begin
  Result := False;
  if UserId <= 0 then
    Exit;

  Query := DatabaseModule1.CreateQuery;
  try
    Query.SQL.Text := 'DELETE FROM users WHERE id = :id';
    Query.ParamByName('id').AsInteger := UserId;

    DatabaseModule1.StartTransaction;
    try
      Query.ExecSQL;
      Result := Query.RowsAffected > 0;
      DatabaseModule1.Commit;
    except
      DatabaseModule1.Rollback;
      raise;
    end;
  finally
    Query.Free;
  end;
end;

function TAuthService.ValidateToken(const Token: string): Boolean;
begin
  Result := TJWTManager.ValidateToken(Token);
end;

function TAuthService.ToJsonResponse(const Response: TAuthResponse): string;
var
  JsonObj: TJSONObject;
  UserObj: TJSONObject;
begin
  JsonObj := TJSONObject.Create;
  try
    JsonObj.AddPair('success', TJSONBool.Create(Response.Success));
    JsonObj.AddPair('token', Response.Token);
    JsonObj.AddPair('errorMessage', Response.ErrorMessage);

    if Assigned(Response.User) then
    begin
      UserObj := TJSONObject.Create;
      try
        UserObj.AddPair('id', TJSONNumber.Create(Response.User.Id));
        UserObj.AddPair('username', Response.User.Username);
        UserObj.AddPair('email', Response.User.Email);
        UserObj.AddPair('role', TJSONNumber.Create(Ord(Response.User.Role)));
        JsonObj.AddPair('user', UserObj);
      except
        UserObj.Free;
        raise;
      end;
    end
    else
      JsonObj.AddPair('user', TJSONNull.Create);

    Result := JsonObj.ToJSON;
  finally
    JsonObj.Free;
  end;
end;

end.
