//unit AuthMiddleware;
//
//interface
//
//uses
//  Horse,
//  Horse.Core.RouterTree,
//  Horse.Core.Route,
//  Horse.Request,
//  Horse.Response,
//  Horse.Commons,
//  Web.HTTPApp,
//  System.SysUtils,
//  System.JSON,
//  System.Classes,
//  System.Generics.Collections,
//  Data.DB,
//  JWTManager,
//  UserModel;
//
//procedure ConfigureAuthMiddleware(App: THorse);
//
//implementation
//
//procedure ApplyAuthMiddleware(Req: THorseRequest; Res: THorseResponse; Next: TProc);
//var
//  AuthHeader: string;
//  Token: string;
//  Claims: TJWTClaims;
//  ErrorObj: TJSONObject;
//begin
//  try
//    // Skip authentication for public endpoints
//    if (Req.RawWebRequest.PathInfo = '/auth/login') or
//       (Req.RawWebRequest.PathInfo = '/auth/register') then
//    begin
//      Next;
//      Exit;
//    end;
//
//    // Get Authorization header
//    AuthHeader := Req.Headers['Authorization'];
//    if AuthHeader.IsEmpty then
//    begin
//      ErrorObj := TJSONObject.Create;
//      try
//        ErrorObj.AddPair('error', 'Authorization header is required');
//        Res.Status(401).Send<TJSONObject>(ErrorObj);
//      except
//        ErrorObj.Free;
//        raise;
//      end;
//      Exit;
//    end;
//
//    // Extract token
//    if not AuthHeader.StartsWith('Bearer ', True) then
//    begin
//      ErrorObj := TJSONObject.Create;
//      try
//        ErrorObj.AddPair('error', 'Invalid authorization format');
//        Res.Status(401).Send<TJSONObject>(ErrorObj);
//      except
//        ErrorObj.Free;
//        raise;
//      end;
//      Exit;
//    end;
//
//    Token := AuthHeader.Substring(7);
//
//    // Validate token and extract claims
//    if not TJWTManager.ValidateToken(Token, Claims) then
//    begin
//      ErrorObj := TJSONObject.Create;
//      try
//        ErrorObj.AddPair('error', 'Invalid or expired token');
//        Res.Status(401).Send<TJSONObject>(ErrorObj);
//      except
//        ErrorObj.Free;
//        raise;
//      end;
//      Exit;
//    end;
//
//    // Store claims in request for later use
//    Req.Query.Dictionary.AddOrSetValue('user-id', Claims.UserId.ToString);
//    Req.Query.Dictionary.AddOrSetValue('user-role', IntToStr(Integer(Claims.Role)));
//    Req.Query.Dictionary.AddOrSetValue('username', Claims.Username);
//
//    Next;
//  except
//    on E: Exception do
//    begin
//      ErrorObj := TJSONObject.Create;
//      try
//        ErrorObj.AddPair('error', 'Authentication error: ' + E.Message);
//        Res.Status(500).Send<TJSONObject>(ErrorObj);
//      except
//        ErrorObj.Free;
//        raise;
//      end;
//    end;
//  end;
//end;
//
//procedure CheckAdminAccess(Req: THorseRequest; Res: THorseResponse; Next: TProc);
//var
//  UserRole: TUserRole;
//  ErrorObj: TJSONObject;
//begin
//  UserRole := TUserRole(StrToIntDef(Req.Query['user-role'], 0));
//
//  if UserRole <> urAdmin then
//  begin
//    ErrorObj := TJSONObject.Create;
//    try
//      ErrorObj.AddPair('error', 'Admin access required');
//      Res.Status(403).Send<TJSONObject>(ErrorObj);
//    except
//      ErrorObj.Free;
//      raise;
//    end;
//    Exit;
//  end;
//
//  Next;
//end;
//
//procedure CheckStockOfficerOrAdminAccess(Req: THorseRequest; Res: THorseResponse; Next: TProc);
//var
//  UserRole: TUserRole;
//  ErrorObj: TJSONObject;
//begin
//  UserRole := TUserRole(StrToIntDef(Req.Query['user-role'], 0));
//
//  if not (UserRole in [urAdmin, urStockOfficer]) then
//  begin
//    ErrorObj := TJSONObject.Create;
//    try
//      ErrorObj.AddPair('error', 'Stock officer or admin access required');
//      Res.Status(403).Send<TJSONObject>(ErrorObj);
//    except
//      ErrorObj.Free;
//      raise;
//    end;
//    Exit;
//  end;
//
//  Next;
//end;
//
//procedure ConfigureAuthMiddleware(App: THorse);
//begin
//  // Apply global authentication middleware
//  App.Use(ApplyAuthMiddleware);
//
//  // Configure route-specific middleware
//  App.Get('/products',
//    procedure(Req: THorseRequest; Res: THorseResponse; Next: TProc)
//    begin
//      CheckStockOfficerOrAdminAccess(Req, Res, Next);
//    end);
//
//  App.Get('/products/:id',
//    procedure(Req: THorseRequest; Res: THorseResponse; Next: TProc)
//    begin
//      CheckStockOfficerOrAdminAccess(Req, Res, Next);
//    end);
//
//  App.Post('/products',
//    procedure(Req: THorseRequest; Res: THorseResponse; Next: TProc)
//    begin
//      CheckAdminAccess(Req, Res, Next);
//    end);
//
//  App.Put('/products/:id',
//    procedure(Req: THorseRequest; Res: THorseResponse; Next: TProc)
//    begin
//      CheckAdminAccess(Req, Res, Next);
//    end);
//
//  App.Delete('/products/:id',
//    procedure(Req: THorseRequest; Res: THorseResponse; Next: TProc)
//    begin
//      CheckAdminAccess(Req, Res, Next);
//    end);
//
//  App.Post('/products/:id/sell',
//    procedure(Req: THorseRequest; Res: THorseResponse; Next: TProc)
//    begin
//      CheckStockOfficerOrAdminAccess(Req, Res, Next);
//    end);
//
//  App.Get('/notifications',
//    procedure(Req: THorseRequest; Res: THorseResponse; Next: TProc)
//    begin
//      CheckStockOfficerOrAdminAccess(Req, Res, Next);
//    end);
//end;
//
//end.
