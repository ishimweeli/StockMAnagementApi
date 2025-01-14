unit UserController;

interface

uses
  Horse,
  System.JSON,
  System.SysUtils,
  System.Classes,
  System.StrUtils,
  FireDAC.Stan.Param,
  UserService,
  UserModel,
  JsonResponseHelper;

type
  // Custom exception classes
  EUserAuthenticationError = class(Exception);
  EUserAuthorizationError = class(Exception);
  EUserValidationError = class(Exception);

  TRequestAuthenticator = class
  public
    class function GetUserIdFromToken(Req: THorseRequest; out UserId: Integer): Boolean;
    class function ValidateUserAccess(Req: THorseRequest; RequiredRole: TUserRole = urStockOfficer): Boolean;
  end;

  TAuthController = class
  private
    FAuthService: TAuthService;

    // Helper methods
    function GetJsonFromRequest(Req: THorseRequest; out JsonObj: TJSONObject;
      out ResponseJson: TJSONObject; Res: THorseResponse): Boolean;
    procedure HandleException(E: Exception; Res: THorseResponse);
    function ValidateRequiredFields(const JsonObj: TJSONObject;
      const Fields: array of string; out MissingField: string): Boolean;
    function ValidateUserPermission(const Req: THorseRequest; const UserId: Integer;
      out ResponseJson: TJSONObject): Boolean;

  public
    constructor Create(AAuthService: TAuthService);
    destructor Destroy; override;

    // Auth endpoints
    procedure Register(Req: THorseRequest; Res: THorseResponse);
    procedure Login(Req: THorseRequest; Res: THorseResponse);

    // User management endpoints
    procedure GetUserProfile(Req: THorseRequest; Res: THorseResponse);
    procedure UpdateUserProfile(Req: THorseRequest; Res: THorseResponse);
    procedure ChangePassword(Req: THorseRequest; Res: THorseResponse);
    procedure DeleteUser(Req: THorseRequest; Res: THorseResponse);
  end;

implementation

{ TRequestAuthenticator }

class function TRequestAuthenticator.GetUserIdFromToken(Req: THorseRequest; out UserId: Integer): Boolean;
var
  AuthHeader: string;
  Token: string;
begin
  Result := False;
  UserId := 0;

  AuthHeader := Req.Headers['Authorization'];
  if AuthHeader.StartsWith('Bearer ', True) then
  begin
    Token := AuthHeader.Replace('Bearer ', '', [rfIgnoreCase]);
    if not Token.IsEmpty then
    begin
      UserId := TJWTManager.GetUserIdFromToken(Token);
      Result := UserId > 0;
    end;
  end;
end;

class function TRequestAuthenticator.ValidateUserAccess(Req: THorseRequest;
  RequiredRole: TUserRole = urStockOfficer): Boolean;
var
  AuthHeader: string;
  Token: string;
  UserRole: TUserRole;
begin
  Result := False;

  AuthHeader := Req.Headers['Authorization'];
  if AuthHeader.StartsWith('Bearer ', True) then
  begin
    Token := AuthHeader.Replace('Bearer ', '', [rfIgnoreCase]);
    if not Token.IsEmpty then
    begin
      UserRole := TJWTManager.GetRoleFromToken(Token);
      Result := Ord(UserRole) >= Ord(RequiredRole);
    end;
  end;
end;

{ TAuthController }

constructor TAuthController.Create(AAuthService: TAuthService);
begin
  inherited Create;
  FAuthService := AAuthService;
end;

destructor TAuthController.Destroy;
begin
  FAuthService.Free;
  inherited;
end;

function TAuthController.ValidateRequiredFields(const JsonObj: TJSONObject;
  const Fields: array of string; out MissingField: string): Boolean;
var
  Field: string;
begin
  Result := True;
  for Field in Fields do
  begin
    if not (JsonObj.GetValue(Field) is TJSONString) or
       (JsonObj.GetValue<string>(Field).Trim.IsEmpty) then
    begin
      MissingField := Field;
      Result := False;
      Exit;
    end;
  end;
end;

function TAuthController.GetJsonFromRequest(Req: THorseRequest;
  out JsonObj: TJSONObject; out ResponseJson: TJSONObject;
  Res: THorseResponse): Boolean;
begin
  Result := False;
  JsonObj := nil;
  ResponseJson := nil;

  if Req.Body.Trim.IsEmpty then
  begin
    ResponseJson := TJsonResponseHelper.CreateError('Request body is required');
    Res.Status(400).Send<TJSONObject>(ResponseJson);
    Exit;
  end;

  try
    JsonObj := TJSONObject.ParseJSONValue(Req.Body) as TJSONObject;
    if not Assigned(JsonObj) then
    begin
      ResponseJson := TJsonResponseHelper.CreateError('Invalid JSON format');
      Res.Status(400).Send<TJSONObject>(ResponseJson);
      Exit;
    end;
    Result := True;
  except
    on E: Exception do
    begin
      ResponseJson := TJsonResponseHelper.CreateError('Invalid JSON format: ' + E.Message);
      Res.Status(400).Send<TJSONObject>(ResponseJson);
    end;
  end;
end;

function TAuthController.ValidateUserPermission(const Req: THorseRequest;
  const UserId: Integer; out ResponseJson: TJSONObject): Boolean;
var
  TokenUserId: Integer;
begin
  Result := False;

  if not TRequestAuthenticator.GetUserIdFromToken(Req, TokenUserId) then
  begin
    ResponseJson := TJsonResponseHelper.CreateError('Invalid authentication token', 401);
    Exit;
  end;

  // Allow access if user is accessing their own data or is an admin
  if (TokenUserId = UserId) or TRequestAuthenticator.ValidateUserAccess(Req, urAdmin) then
    Result := True
  else
    ResponseJson := TJsonResponseHelper.CreateError('Unauthorized access', 403);
end;

procedure TAuthController.HandleException(E: Exception; Res: THorseResponse);
var
  ResponseJson: TJSONObject;
  StatusCode: Integer;
begin
  StatusCode := 500;

  // Handle specific exceptions with appropriate status codes
  if E is EUserAuthenticationError then
    StatusCode := 401
  else if E is EUserAuthorizationError then
    StatusCode := 403
  else if E is EUserValidationError then
    StatusCode := 400;

  ResponseJson := TJsonResponseHelper.CreateError(E.Message, StatusCode);
  Res.Status(StatusCode)
     .ContentType('application/json')
     .Send<TJSONObject>(ResponseJson);
end;


procedure TAuthController.Register(Req: THorseRequest; Res: THorseResponse);
var
  JsonObj: TJSONObject;
  AuthResponse: TAuthResponse;
  Role: TUserRole;
  ResponseJson: TJSONObject;
  MissingField: string;
begin
  if not GetJsonFromRequest(Req, JsonObj, ResponseJson, Res) then
    Exit;
  try
    if not ValidateRequiredFields(JsonObj, ['username', 'password', 'email'], MissingField) then
    begin
      ResponseJson := TJsonResponseHelper.CreateError(Format('%s is required', [MissingField]));
      Res.Status(400).Send<TJSONObject>(ResponseJson);
      Exit;
    end;

    // Set role from JSON if provided, otherwise default to StockOfficer
    if JsonObj.GetValue('role') <> nil then
      Role := TUserRole(JsonObj.GetValue<Integer>('role'))
    else
      Role := urStockOfficer;

    AuthResponse := FAuthService.Register(
      JsonObj.GetValue<string>('username'),
      JsonObj.GetValue<string>('password'),
      JsonObj.GetValue<string>('email'),
      Role
    );

    if AuthResponse.Success then
      Res.Status(201)
         .ContentType('application/json')
         .Send<TJSONObject>(TJsonResponseHelper.CreateAuthSuccess(AuthResponse.User, AuthResponse.Token))
    else
      Res.Status(400)
         .ContentType('application/json')
         .Send<TJSONObject>(TJsonResponseHelper.CreateError(AuthResponse.ErrorMessage));
  except
    on E: Exception do
      HandleException(E, Res);
  end;
  JsonObj.Free;
end;

procedure TAuthController.Login(Req: THorseRequest; Res: THorseResponse);
var
  JsonObj: TJSONObject;
  AuthResponse: TAuthResponse;
  ResponseJson: TJSONObject;
  MissingField: string;
begin
  if not GetJsonFromRequest(Req, JsonObj, ResponseJson, Res) then
    Exit;

  try
    if not ValidateRequiredFields(JsonObj, ['username', 'password'], MissingField) then
    begin
      ResponseJson := TJsonResponseHelper.CreateError(Format('%s is required', [MissingField]));
      Res.Status(400).Send<TJSONObject>(ResponseJson);
      Exit;
    end;

    AuthResponse := FAuthService.Login(
      JsonObj.GetValue<string>('username'),
      JsonObj.GetValue<string>('password')
    );

    if AuthResponse.Success then
      Res.Status(200)
         .ContentType('application/json')
         .Send<TJSONObject>(TJsonResponseHelper.CreateAuthSuccess(AuthResponse.User, AuthResponse.Token))
    else
      Res.Status(401)
         .ContentType('application/json')
         .Send<TJSONObject>(TJsonResponseHelper.CreateError(
           IfThen(AuthResponse.ErrorMessage.IsEmpty, 'Invalid credentials', AuthResponse.ErrorMessage),
           401
         ));
  except
    on E: Exception do
      HandleException(E, Res);
  end;
  JsonObj.Free;
end;

procedure TAuthController.GetUserProfile(Req: THorseRequest; Res: THorseResponse);
var
  UserId: Integer;
  User: TUser;
  ResponseJson: TJSONObject;
begin
  try
    UserId := StrToIntDef(Req.Params['id'], 0);
    if UserId = 0 then
    begin
      ResponseJson := TJsonResponseHelper.CreateError('Invalid user ID', 400);
      Res.Status(400).Send<TJSONObject>(ResponseJson);
      Exit;
    end;

    if not ValidateUserPermission(Req, UserId, ResponseJson) then
    begin
      Res.Status(403).Send<TJSONObject>(ResponseJson);
      Exit;
    end;

    User := FAuthService.GetUserProfile(UserId);
    if Assigned(User) then
    try
      ResponseJson := TJsonResponseHelper.CreateSuccess('User profile retrieved successfully',
        TJSONObject.Create
          .AddPair('id', TJSONNumber.Create(User.Id))
          .AddPair('username', User.Username)
          .AddPair('email', User.Email)
          .AddPair('role', TJSONNumber.Create(Ord(User.Role)))
      );
      Res.Status(200)
         .ContentType('application/json')
         .Send<TJSONObject>(ResponseJson);
    finally
      User.Free;
    end
    else
    begin
      ResponseJson := TJsonResponseHelper.CreateError('User not found', 404);
      Res.Status(404)
         .ContentType('application/json')
         .Send<TJSONObject>(ResponseJson);
    end;
  except
    on E: Exception do
      HandleException(E, Res);
  end;
end;

procedure TAuthController.UpdateUserProfile(Req: THorseRequest; Res: THorseResponse);
var
  JsonObj: TJSONObject;
  ResponseJson: TJSONObject;
  UserId: Integer;
begin
  if not GetJsonFromRequest(Req, JsonObj, ResponseJson, Res) then
    Exit;

  try
    UserId := StrToIntDef(Req.Params['id'], 0);
    if UserId = 0 then
    begin
      ResponseJson := TJsonResponseHelper.CreateError('Invalid user ID', 400);
      Res.Status(400).Send<TJSONObject>(ResponseJson);
      Exit;
    end;

    if not ValidateUserPermission(Req, UserId, ResponseJson) then
    begin
      Res.Status(403).Send<TJSONObject>(ResponseJson);
      Exit;
    end;

    if FAuthService.UpdateUserProfile(
      UserId,
      JsonObj.GetValue<string>('email', ''),
      JsonObj.GetValue<string>('username', '')
    ) then
      Res.Status(200)
         .ContentType('application/json')
         .Send<TJSONObject>(TJsonResponseHelper.CreateSuccess('Profile updated successfully'))
    else
      Res.Status(400)
         .ContentType('application/json')
         .Send<TJSONObject>(TJsonResponseHelper.CreateError('Failed to update profile'));
  except
    on E: Exception do
      HandleException(E, Res);
  end;
  JsonObj.Free;
end;

procedure TAuthController.ChangePassword(Req: THorseRequest; Res: THorseResponse);
var
  JsonObj: TJSONObject;
  ResponseJson: TJSONObject;
  UserId: Integer;
  MissingField: string;
begin
  if not GetJsonFromRequest(Req, JsonObj, ResponseJson, Res) then
    Exit;

  try
    UserId := StrToIntDef(Req.Params['id'], 0);
    if UserId = 0 then
    begin
      ResponseJson := TJsonResponseHelper.CreateError('Invalid user ID', 400);
      Res.Status(400).Send<TJSONObject>(ResponseJson);
      Exit;
    end;

    if not ValidateUserPermission(Req, UserId, ResponseJson) then
    begin
      Res.Status(403).Send<TJSONObject>(ResponseJson);
      Exit;
    end;

    if not ValidateRequiredFields(JsonObj, ['currentPassword', 'newPassword'], MissingField) then
    begin
      ResponseJson := TJsonResponseHelper.CreateError(Format('%s is required', [MissingField]));
      Res.Status(400).Send<TJSONObject>(ResponseJson);
      Exit;
    end;

    if FAuthService.ChangePassword(
      UserId,
      JsonObj.GetValue<string>('currentPassword'),
      JsonObj.GetValue<string>('newPassword')
    ) then
      Res.Status(200)
         .ContentType('application/json')
         .Send<TJSONObject>(TJsonResponseHelper.CreateSuccess('Password changed successfully'))
    else
      Res.Status(400)
         .ContentType('application/json')
         .Send<TJSONObject>(TJsonResponseHelper.CreateError('Failed to change password'));
  except
    on E: Exception do
      HandleException(E, Res);
  end;
  JsonObj.Free;
end;

procedure TAuthController.DeleteUser(Req: THorseRequest; Res: THorseResponse);
var
  ResponseJson: TJSONObject;
  UserId: Integer;
  Success: Boolean;
begin
  try
    UserId := StrToIntDef(Req.Params['id'], 0);
    if UserId = 0 then
    begin
      ResponseJson := TJsonResponseHelper.CreateError('Invalid user ID', 400);
      Res.Status(400).Send<TJSONObject>(ResponseJson);
      Exit;
    end;

    // Validate that only admins or the user themselves can delete their account
    if not ValidateUserPermission(Req, UserId, ResponseJson) then
    begin
      Res.Status(403).Send<TJSONObject>(ResponseJson);
      Exit;
    end;

    Success := FAuthService.DeleteUser(UserId);
    if Success then
    begin
      ResponseJson := TJsonResponseHelper.CreateSuccess('User deleted successfully');
      Res.Status(200)
         .ContentType('application/json')
         .Send<TJSONObject>(ResponseJson);
    end
    else
    begin
      ResponseJson := TJsonResponseHelper.CreateError('Failed to delete user');
      Res.Status(400)
         .ContentType('application/json')
         .Send<TJSONObject>(ResponseJson);
    end;
  except
    on E: Exception do
      HandleException(E, Res);
  end;
end;

end.
