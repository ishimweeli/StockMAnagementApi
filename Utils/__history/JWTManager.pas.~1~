   unit JsonResponseHelper;

interface

uses
  System.JSON, UserModel;

type
  TJsonResponseHelper = class
  public
    class function CreateSuccess(const Message: string = ''; Data: TJSONValue = nil): TJSONObject;
    class function CreateError(const ErrorMessage: string; StatusCode: Integer = 400): TJSONObject;
    class function CreateAuthSuccess(User: TUser; const Token: string): TJSONObject;
  end;

implementation

class function TJsonResponseHelper.CreateSuccess(const Message: string = ''; Data: TJSONValue = nil): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('success', TJSONBool.Create(True));

  if Message <> '' then
    Result.AddPair('message', Message);

  if Assigned(Data) then
    Result.AddPair('data', Data);
end;

class function TJsonResponseHelper.CreateError(const ErrorMessage: string; StatusCode: Integer = 400): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('success', TJSONBool.Create(False));
  Result.AddPair('error', TJSONObject.Create
    .AddPair('message', ErrorMessage)
    .AddPair('code', TJSONNumber.Create(StatusCode)));
end;

class function TJsonResponseHelper.CreateAuthSuccess(User: TUser; const Token: string): TJSONObject;
var
  UserJson, DataJson: TJSONObject;
begin
  UserJson := TJSONObject.Create;
  UserJson.AddPair('id', TJSONNumber.Create(User.Id));
  UserJson.AddPair('username', User.Username);
  UserJson.AddPair('email', User.Email);
  UserJson.AddPair('role', TJSONNumber.Create(Ord(User.Role)));

  DataJson := TJSONObject.Create;
  DataJson.AddPair('user', UserJson);
  DataJson.AddPair('token', Token);

  Result := CreateSuccess('Authentication successful', DataJson);
end;

end.
