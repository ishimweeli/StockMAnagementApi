//unit WebModuleUnit1;
//
//interface
//
//uses
//  System.SysUtils, System.Classes, Web.HTTPApp, System.JSON;
//
//type
//  TWebModule1 = class(TWebModule)
//    procedure WebModule1DefaultHandlerAction(Sender: TObject;
//      Request: TWebRequest; Response: TWebResponse; var Handled: Boolean);
//  private
//    { Private declarations }
//  public
//    { Public declarations }
//  end;
//
//var
//  WebModuleClass: TComponentClass = TWebModule1;
//
//implementation
//
//{%CLASSGROUP 'System.Classes.TPersistent'}
//{$R *.dfm}
//
//procedure TWebModule1.WebModule1DefaultHandlerAction(Sender: TObject;
//  Request: TWebRequest; Response: TWebResponse; var Handled: Boolean);
//var
//  JsonResponse: TJSONObject;
//begin
//  JsonResponse := TJSONObject.Create;
//  try
//    JsonResponse.AddPair('success', TJSONBool.Create(True));
//    JsonResponse.AddPair('message', 'Endpoint reached successfully');
//
//    Response.ContentType := 'application/json';
//    Response.Content := JsonResponse.ToString;
//    Response.StatusCode := 200;
//  finally
//    JsonResponse.Free;
//  end;
//end;
//
//end.

