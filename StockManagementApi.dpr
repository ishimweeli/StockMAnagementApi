program StockManagementApi;
{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.JSON,
  Horse,
  Horse.Jhonson,
  Horse.JWT,
  Horse.BasicAuthentication,
  Horse.CORS,
  JOSE.Core.JWT,
  JOSE.Core.Builder,
  JOSE.Core.JWA,
  JOSE.Types.JSON,
  FireDAC.Stan.Param,
  DatabaseModule in 'DatabaseModule.pas',
  UserModel in 'Models\UserModel.pas',
  ProductModel in 'Models\ProductModel.pas',
  UserService in 'Service\UserService.pas',
  ProductService in 'Service\ProductService.pas',
  UserController in 'Controller\UserController.pas',
  ProductController in 'Controller\ProductController.pas',
  JsonResponseHelper in 'Utils\JsonResponseHelper.pas',
  CORSMiddleware in 'Middleware\CORSMiddleware.pas',
  NotificationModel in 'Models\NotificationModel.pas';

const
  SECRET_KEY = 'your-secret-key-here';
  TOKEN_EXPIRY_HOURS = 24;

resourcestring
  ERR_NO_TOKEN = 'No authorization token provided';
  ERR_UNAUTHORIZED = 'Unauthorized: Insufficient role permissions';
  ERR_INVALID_TOKEN = 'Invalid or expired token';

type
  TNextProc = TProc;

  TJWTClaims = record
    UserId: Integer;
    Username: string;
    Role: UserModel.TUserRole;
    constructor Create(AUserId: Integer; const AUsername: string; ARole: UserModel.TUserRole);
  end;

{ TJWTClaims }

constructor TJWTClaims.Create(AUserId: Integer; const AUsername: string; ARole: UserModel.TUserRole);
begin
  UserId := AUserId;
  Username := AUsername;
  Role := ARole;
end;


function ValidateToken(const Token: string): Boolean;
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

function GetUserIdFromToken(const Token: string): Integer;
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

function GetRoleFromToken(const Token: string): UserModel.TUserRole;
var
  JWT: TJWT;
  RoleValue: TJSONValue;
begin
  Result := UserModel.TUserRole.urAdmin;
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

procedure RoleMiddleware(Req: THorseRequest; Res: THorseResponse; Next: TNextProc;
  RequiredRole: UserModel.TUserRole);
var
  Token: string;
  TokenRole: UserModel.TUserRole;
begin
  Token := Req.Headers['Authorization'];
  if Token.IsEmpty then
  begin
    Res.Status(THTTPStatus.Unauthorized)
       .Send<TJSONObject>(TJSONObject.Create.AddPair('error', ERR_NO_TOKEN));
    Exit;
  end;

  if Token.StartsWith('Bearer ', True) then
    Token := Token.Substring(7);

  try
    if ValidateToken(Token) then
    begin
      TokenRole := GetRoleFromToken(Token);
      if (TokenRole = urAdmin) or (TokenRole = RequiredRole) then
        Next()
      else
        Res.Status(THTTPStatus.Forbidden)
           .Send<TJSONObject>(TJSONObject.Create.AddPair('error', ERR_UNAUTHORIZED));
    end
    else
      Res.Status(THTTPStatus.Unauthorized)
         .Send<TJSONObject>(TJSONObject.Create.AddPair('error', ERR_INVALID_TOKEN));
  except
    on E: Exception do
      Res.Status(THTTPStatus.Unauthorized)
         .Send<TJSONObject>(TJSONObject.Create.AddPair('error', 'Token validation error: ' + E.Message));
  end;
end;

procedure AuthMiddleware(Req: THorseRequest; Res: THorseResponse; Next: TNextProc);
var
  Token: string;
begin
  Token := Req.Headers['Authorization'];
  if Token.IsEmpty then
  begin
    Res.Status(THTTPStatus.Unauthorized)
       .Send<TJSONObject>(TJSONObject.Create.AddPair('error', ERR_NO_TOKEN));
    Exit;
  end;

  if Token.StartsWith('Bearer ', True) then
    Token := Token.Substring(7);

  try
    if ValidateToken(Token) then
      Next()
    else
      Res.Status(THTTPStatus.Unauthorized)
         .Send<TJSONObject>(TJSONObject.Create.AddPair('error', ERR_INVALID_TOKEN));
  except
    on E: Exception do
      Res.Status(THTTPStatus.Unauthorized)
         .Send<TJSONObject>(TJSONObject.Create.AddPair('error', ERR_INVALID_TOKEN));
  end;
end;

procedure ConfigurePublicRoutes(App: THorse; AuthController: TAuthController);
begin
  App.Post('/auth/register',
    procedure(Req: THorseRequest; Res: THorseResponse; Next: TProc)
    begin
      AuthController.Register(Req, Res);
    end);

  App.Post('/auth/login',
    procedure(Req: THorseRequest; Res: THorseResponse; Next: TProc)
    begin
      AuthController.Login(Req, Res);
    end);
end;

procedure ConfigureUserRoutes(App: THorse; AuthController: TAuthController);
begin
  App.Get('/users/:id',
    procedure(Req: THorseRequest; Res: THorseResponse; Next: TProc)
    begin
      AuthController.GetUserProfile(Req, Res);
    end);

  App.Put('/users/:id',
    procedure(Req: THorseRequest; Res: THorseResponse; Next: TProc)
    begin
      AuthController.UpdateUserProfile(Req, Res);
    end);
end;

procedure ConfigureAdminRoutes(App: THorse; ProductController: TProductController);
begin
  App.Post('/products',
    procedure(Req: THorseRequest; Res: THorseResponse; Next: TProc)
    begin
      RoleMiddleware(Req, Res,
        procedure
        begin
          ProductController.AddItem(Req, Res);
        end, urAdmin);
    end);

  App.Put('/products/:id',
    procedure(Req: THorseRequest; Res: THorseResponse; Next: TProc)
    begin
      RoleMiddleware(Req, Res,
        procedure
        begin
          ProductController.UpdateItem(Req, Res);
        end, urAdmin);
    end);

  App.Delete('/products/:id',
    procedure(Req: THorseRequest; Res: THorseResponse; Next: TProc)
    begin
      RoleMiddleware(Req, Res,
        procedure
        begin
          ProductController.DeleteItem(Req, Res);
        end, urAdmin);
    end);
end;

procedure ConfigureStockOfficerRoutes(App: THorse; ProductController: TProductController);
begin
  App.Post('/products/:id/sell',
    procedure(Req: THorseRequest; Res: THorseResponse; Next: TProc)
    begin
      RoleMiddleware(Req, Res,
        procedure
        begin
          ProductController.SellItem(Req, Res);
        end, urStockOfficer);
    end);
end;

procedure ConfigureProductRoutes(App: THorse; ProductController: TProductController);
begin
  App.Get('/products',
    procedure(Req: THorseRequest; Res: THorseResponse; Next: TProc)
    begin
      ProductController.GetItems(Req, Res);
    end);

  App.Get('/products/:id',
    procedure(Req: THorseRequest; Res: THorseResponse; Next: TProc)
    begin
      ProductController.GetItemById(Req, Res);
    end);

  App.Get('/notifications',
    procedure(Req: THorseRequest; Res: THorseResponse; Next: TProc)
    begin
      ProductController.GetNotifications(Req, Res);
    end);
end;

var
  App: THorse;
  AuthService: TAuthService;
  ProductService: TProductService;
  AuthController: TAuthController;
  ProductController: TProductController;
  DatabaseModule1: TDatabaseConnection;

begin
  try
    DatabaseModule1 := TDatabaseConnection.Create;
    try
      DatabaseModule1.Connect;

      App := THorse.Create;
      try
        AuthService := TAuthService.Create;
        ProductService := TProductService.Create;
        try
          AuthController := TAuthController.Create(AuthService);
          ProductController := TProductController.Create(ProductService);
          try
            // Configure Middleware
            App.Use(Jhonson);
            App.Use(CORS);

            // Configure Routes
            ConfigurePublicRoutes(App, AuthController);
            App.Use(AuthMiddleware);  // Add Authentication Middleware for protected routes

            // Configure Protected Routes
            ConfigureUserRoutes(App, AuthController);
            ConfigureAdminRoutes(App, ProductController);
            ConfigureStockOfficerRoutes(App, ProductController);
            ConfigureProductRoutes(App, ProductController);

            // Start server
            WriteLn('Starting server on port 8000...');
            App.Listen(8000);
            WriteLn('Server is running on port 8000');
            WriteLn('Press Enter to stop...');
            ReadLn;

          finally
            ProductController.Free;
            AuthController.Free;
          end;
        finally
          ProductService.Free;
          AuthService.Free;
        end;
      finally
        App.Free;
      end;
    finally
      DatabaseModule1.Free;
    end;
  except
    on E: Exception do
    begin
      Writeln(E.ClassName, ': ', E.Message);
      Readln;
    end;
  end;
end.
