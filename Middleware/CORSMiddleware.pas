
unit CORSMiddleware;

interface

uses
  Horse, System.SysUtils;

procedure ConfigureCORS(App: THorse);

implementation

procedure ConfigureCORS(App: THorse);
begin
  App.Use(
    procedure(Req: THorseRequest; Res: THorseResponse; Next: TProc)
    begin
      // Set CORS headers
      Res.RawWebResponse.SetCustomHeader('Access-Control-Allow-Origin', '*');
      Res.RawWebResponse.SetCustomHeader('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
      Res.RawWebResponse.SetCustomHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');
      Res.RawWebResponse.SetCustomHeader('Access-Control-Allow-Credentials', 'true');

      // Handle preflight requests
      if SameText(Req.RawWebRequest.Method, 'OPTIONS') then
      begin
        Res.Status(200);  // Changed to 200 OK
        Res.RawWebResponse.Content := '';
        Res.RawWebResponse.SendResponse;
      end
      else
        Next();
    end
  );
end;

end.

// Then, update your AuthController.pas
unit AuthController;

interface

uses
  Horse,
  System.JSON,
  System.SysUtils;

type
  TAuthController = class
  private
    FAuthService: TAuthService;
  public
    constructor Create(AAuthService: TAuthService);
    procedure Login(Req: THorseRequest; Res: THorseResponse);
  end;

implementation

constructor TAuthController.Create(AAuthService: TAuthService);
begin
  FAuthService := AAuthService;
end;

procedure TAuthController.Login(Req: THorseRequest; Res: THorseResponse);
var
  JsonBody: TJSONObject;
  Email, Password: string;
begin
  try
    // Parse request body
    JsonBody := TJSONObject.ParseJSONValue(Req.Body) as TJSONObject;
    try
      if not Assigned(JsonBody) then
        raise EHorseException.Create('Invalid request body');

      // Extract credentials
      Email := JsonBody.GetValue<string>('email');
      Password := JsonBody.GetValue<string>('password');

      // Validate input
      if (Email.IsEmpty) or (Password.IsEmpty) then
        raise EHorseException.Create('Email and password are required');

      // Attempt login
      var Token := FAuthService.Login(Email, Password);

      // Return success response
      Res.Send<TJSONObject>(
        TJSONObject.Create
          .AddPair('success', TJSONBool.Create(True))
          .AddPair('token', Token)
      ).Status(200);

    finally
      JsonBody.Free;
    end;

  except
    on E: EHorseException do
      Res.Send<TJSONObject>(
        TJSONObject.Create
          .AddPair('success', TJSONBool.Create(False))
          .AddPair('error', E.Message)
      ).Status(400);
    on E: Exception do
      Res.Send<TJSONObject>(
        TJSONObject.Create
          .AddPair('success', TJSONBool.Create(False))
          .AddPair('error', 'Internal server error')
      ).Status(500);
  end;
end;

end.
