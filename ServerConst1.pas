//unit ServerConst1;
//
//interface
//
//uses
//  Horse,
//  System.SysUtils,
//  System.JSON,
//  DatabaseModule,
//  UserController,
//  UserService;
//
//procedure StartServer;
//
//implementation
//
//var
//  AuthController: TAuthController;
//  AuthService: TAuthService;
//
//procedure StartServer;
//begin
//  try
//    // Set global middleware for JSON responses
//    THorse.Use(
//      procedure(Req: THorseRequest; Res: THorseResponse; Next: TProc)
//      begin
//        Res.ContentType('application/json; charset=utf-8');
//        try
//          Next();
//        except
//          on E: Exception do
//          begin
//            var ErrorJson := TJSONObject.Create;
//            try
//              ErrorJson
//                .AddPair('success', TJSONBool.Create(False))
//                .AddPair('error', TJSONObject.Create
//                  .AddPair('message', E.Message)
//                  .AddPair('type', E.ClassName));
//              Res.Send(ErrorJson).Status(500);
//            except
//              ErrorJson.Free;
//              raise;
//            end;
//          end;
//        end;
//      end
//    );
//
//    // Initialize database connection
//    if not Assigned(DatabaseModule1) then
//      DatabaseModule1 := TDatabaseConnection.Create;
//    DatabaseModule1.Connect;
//
//    // Initialize services and controllers
//    AuthService := TAuthService.Create;
//    AuthController := TAuthController.Create(AuthService);
//
//    // Default route handler
//    THorse.Get('/api',
//      procedure(Req: THorseRequest; Res: THorseResponse)
//      var
//        ResponseJson: TJSONObject;
//      begin
//        ResponseJson := TJSONObject.Create;
//        try
//          ResponseJson
//            .AddPair('success', TJSONBool.Create(True))
//            .AddPair('message', 'API Server Running')
//            .AddPair('version', '1.0');
//          Res.Send(ResponseJson).Status(200);
//        except
//          ResponseJson.Free;
//          raise;
//        end;
//      end
//    );
//
//
//THorse.Post('/auth/login',
//  procedure(Req: THorseRequest; Res: THorseResponse)
//  begin
//    AuthController.Login(Req, Res);
//    Res.ContentType('application/json'); // Ensure the Content-Type is JSON
//  end
//);
//
//
//
//    THorse.Post('/auth/register',
//      procedure(Req: THorseRequest; Res: THorseResponse)
//      begin
//        AuthController.Register(Req, Res);
//      end
//    );
//
//    // 404 handler
//    THorse.Get('/*',
//      procedure(Req: THorseRequest; Res: THorseResponse)
//      var
//        ResponseJson: TJSONObject;
//      begin
//        ResponseJson := TJSONObject.Create;
//        try
//          ResponseJson
//            .AddPair('success', TJSONBool.Create(False))
//            .AddPair('error', TJSONObject.Create
//              .AddPair('message', 'Route not found')
//              .AddPair('path', Req.PathInfo));
//          Res.Send(ResponseJson).Status(404);
//        except
//          ResponseJson.Free;
//          raise;
//        end;
//      end
//    );
//
//    // Start server
//    Writeln('Server is starting on port 8080...');
//    THorse.Listen(8080);
//  except
//    on E: Exception do
//    begin
//      if Assigned(AuthController) then
//        AuthController.Free;
//      if Assigned(AuthService) then
//        AuthService.Free;
//      raise Exception.Create('Server initialization failed: ' + E.Message);
//    end;
//  end;
//end;
//
//initialization
//  AuthController := nil;
//  AuthService := nil;
//
//finalization
//  if Assigned(AuthController) then
//    AuthController.Free;
//  if Assigned(AuthService) then
//    AuthService.Free;
//
//end.

