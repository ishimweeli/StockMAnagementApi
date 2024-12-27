//unit ProductController;
//
//interface
//
//uses
//  Horse,
//  System.JSON,
//  System.SysUtils,
//  System.Classes,
//  System.StrUtils,
//  System.Generics.Collections,
//  ProductService,
//  ProductModel,
//  UserModel,
//  JsonResponseHelper;
//
//type
//  EProductControllerException = class(Exception);
//  EInvalidRequestException = class(EProductControllerException);
//  EValidationException = class(EProductControllerException);
//  EResourceNotFoundException = class(EProductControllerException);
//
//  TProductController = class
//  private
//    FProductService: TProductService;
//
//    function GetJsonFromRequest(Req: THorseRequest; out JsonObj: TJSONObject;
//      out ResponseJson: TJSONObject; Res: THorseResponse): Boolean;
//    procedure HandleException(E: Exception; Res: THorseResponse);
//    function ValidateRequiredFields(const JsonObj: TJSONObject;
//      const Fields: array of string; out MissingField: string): Boolean;
//    function ValidateItemData(const JsonObj: TJSONObject; out Item: TItem;
//      out ResponseJson: TJSONObject): Boolean;
//    procedure SendErrorResponse(const ErrorMsg: string; StatusCode: Integer; Res: THorseResponse);
//
//  public
//    constructor Create(AProductService: TProductService);
//    destructor Destroy; override;
//
//    procedure AddItem(Req: THorseRequest; Res: THorseResponse);
//    procedure UpdateItem(Req: THorseRequest; Res: THorseResponse);
//    procedure DeleteItem(Req: THorseRequest; Res: THorseResponse);
//    procedure GetItems(Req: THorseRequest; Res: THorseResponse);
//    procedure GetItemById(Req: THorseRequest; Res: THorseResponse);
//    procedure SellItem(Req: THorseRequest; Res: THorseResponse);
//    procedure GetNotifications(Req: THorseRequest; Res: THorseResponse);
//  end;
//
//implementation
//
//{ TProductController }
//
//constructor TProductController.Create(AProductService: TProductService);
//begin
//  if not Assigned(AProductService) then
//    raise EInvalidRequestException.Create('Product service cannot be nil');
//
//  inherited Create;
//  FProductService := AProductService;
//end;
//
//destructor TProductController.Destroy;
//begin
//  inherited;
//end;
//
//procedure TProductController.SendErrorResponse(const ErrorMsg: string; StatusCode: Integer;
//  Res: THorseResponse);
//var
//  ResponseJson: TJSONObject;
//begin
//  ResponseJson := TJsonResponseHelper.CreateError(ErrorMsg, StatusCode);
//  Res.Status(StatusCode)
//     .ContentType('application/json')
//     .Send<TJSONObject>(ResponseJson);
//end;
//
//function TProductController.GetJsonFromRequest(Req: THorseRequest;
//  out JsonObj: TJSONObject; out ResponseJson: TJSONObject;
//  Res: THorseResponse): Boolean;
//begin
//  Result := False;
//  JsonObj := nil;
//
//  try
//    if (Req.Body = EmptyStr) then
//      raise EInvalidRequestException.Create('Request body cannot be empty');
//
//    JsonObj := TJSONObject.ParseJSONValue(Req.Body) as TJSONObject;
//    if not Assigned(JsonObj) then
//      raise EInvalidRequestException.Create('Invalid JSON format');
//
//    Result := True;
//  except
//    on E: EInvalidRequestException do
//    begin
//      SendErrorResponse(E.Message, 400, Res);
//      Exit;
//    end;
//    on E: Exception do
//    begin
//      SendErrorResponse('Error processing request: ' + E.Message, 400, Res);
//      Exit;
//    end;
//  end;
//end;
//
//function TProductController.ValidateRequiredFields(const JsonObj: TJSONObject;
//  const Fields: array of string; out MissingField: string): Boolean;
//var
//  Field: string;
//begin
//  Result := True;
//  for Field in Fields do
//  begin
//    if not (JsonObj.TryGetValue<string>(Field, MissingField) or
//            JsonObj.TryGetValue<Integer>(Field, Integer(MissingField)) or
//            JsonObj.TryGetValue<Double>(Field, Double(MissingField))) then
//    begin
//      MissingField := Field;
//      Result := False;
//      Exit;
//    end;
//  end;
//end;
//
//function TProductController.ValidateItemData(const JsonObj: TJSONObject;
//  out Item: TItem; out ResponseJson: TJSONObject): Boolean;
//var
//  MissingField: string;
//begin
//  Result := False;
//  Item := nil;
//
//  try
//    if not ValidateRequiredFields(JsonObj, ['name', 'quantity', 'price'], MissingField) then
//      raise EValidationException.Create(Format('Field "%s" is required', [MissingField]));
//
//    Item := TItem.Create;
//    try
//      Item.Name := JsonObj.GetValue<string>('name');
//      if Item.Name.Trim.IsEmpty then
//        raise EValidationException.Create('Name cannot be empty');
//
//      Item.Quantity := JsonObj.GetValue<Integer>('quantity');
//      if Item.Quantity < 0 then
//        raise EValidationException.Create('Quantity cannot be negative');
//
//      Item.Price := JsonObj.GetValue<Double>('price');
//      if Item.Price <= 0 then
//        raise EValidationException.Create('Price must be greater than zero');
//
//      Result := True;
//    except
//      FreeAndNil(Item);
//      raise;
//    end;
//  except
//    on E: EValidationException do
//      ResponseJson := TJsonResponseHelper.CreateError(E.Message);
//    on E: Exception do
//      ResponseJson := TJsonResponseHelper.CreateError('Invalid item data: ' + E.Message);
//  end;
//end;
//
//procedure TProductController.HandleException(E: Exception; Res: THorseResponse);
//begin
//  if E is EInvalidRequestException then
//    SendErrorResponse(E.Message, 400, Res)
//  else if E is EValidationException then
//    SendErrorResponse(E.Message, 422, Res)
//  else if E is EResourceNotFoundException then
//    SendErrorResponse(E.Message, 404, Res)
//  else
//    SendErrorResponse('Internal server error: ' + E.Message, 500, Res);
//end;
//
//procedure TProductController.AddItem(Req: THorseRequest; Res: THorseResponse);
//var
//  JsonObj: TJSONObject;
//  ResponseJson: TJSONObject;
//  Item: TItem;
//begin
//  if not GetJsonFromRequest(Req, JsonObj, ResponseJson, Res) then
//    Exit;
//
//  try
//    try
//      if not ValidateItemData(JsonObj, Item, ResponseJson) then
//      begin
//        Res.Status(422).Send<TJSONObject>(ResponseJson);
//        Exit;
//      end;
//
//      if FProductService.AddItem(Item) then
//      begin
//        ResponseJson := TJsonResponseHelper.CreateSuccess('Item added successfully');
//        Res.Status(201)
//           .ContentType('application/json')
//           .Send<TJSONObject>(ResponseJson);
//      end
//      else
//        raise EProductControllerException.Create('Failed to add item');
//    finally
//      Item.Free;
//    end;
//  except
//    on E: Exception do
//      HandleException(E, Res);
//  end;
//  JsonObj.Free;
//end;
//
//procedure TProductController.UpdateItem(Req: THorseRequest; Res: THorseResponse);
//var
//  JsonObj: TJSONObject;
//  ResponseJson: TJSONObject;
//  Item: TItem;
//  ItemId: Integer;
//begin
//  if not GetJsonFromRequest(Req, JsonObj, ResponseJson, Res) then
//    Exit;
//
//  try
//    if not TryStrToInt(Req.Params['id'], ItemId) or (ItemId <= 0) then
//      raise EInvalidRequestException.Create('Invalid item ID');
//
//    if not ValidateItemData(JsonObj, Item, ResponseJson) then
//    begin
//      Res.Status(422).Send<TJSONObject>(ResponseJson);
//      Exit;
//    end;
//
//    try
//      if FProductService.UpdateItem(ItemId, Item) then
//      begin
//        ResponseJson := TJsonResponseHelper.CreateSuccess('Item updated successfully');
//        Res.Status(200)
//           .ContentType('application/json')
//           .Send<TJSONObject>(ResponseJson);
//      end
//      else
//        raise EResourceNotFoundException.Create('Item not found');
//    finally
//      Item.Free;
//    end;
//  except
//    on E: Exception do
//      HandleException(E, Res);
//  end;
//  JsonObj.Free;
//end;
//
//procedure TProductController.DeleteItem(Req: THorseRequest; Res: THorseResponse);
//var
//  ItemId: Integer;
//begin
//  try
//    if not TryStrToInt(Req.Params['id'], ItemId) or (ItemId <= 0) then
//      raise EInvalidRequestException.Create('Invalid item ID');
//
//    if not FProductService.DeleteItem(ItemId) then
//      raise EResourceNotFoundException.Create('Item not found');
//
//    Res.Status(200)
//       .ContentType('application/json')
//       .Send<TJSONObject>(TJsonResponseHelper.CreateSuccess('Item deleted successfully'));
//  except
//    on E: Exception do
//      HandleException(E, Res);
//  end;
//end;
//
//procedure TProductController.GetItems(Req: THorseRequest; Res: THorseResponse);
//var
//  Items: TObjectList<TItem>;
//  JsonArray: TJSONArray;
//  ResponseJson: TJSONObject;
//begin
//  try
//    Items := FProductService.GetAllItems;
//    try
//      JsonArray := TJSONArray.Create;
//      try
//        for var Item in Items do
//        begin
//          JsonArray.AddElement(
//            TJSONObject.Create
//              .AddPair('id', TJSONNumber.Create(Item.Id))
//              .AddPair('name', Item.Name)
//              .AddPair('quantity', TJSONNumber.Create(Item.Quantity))
//              .AddPair('price', TJSONNumber.Create(Item.Price))
//          );
//        end;
//
//        ResponseJson := TJsonResponseHelper.CreateSuccess('Items retrieved successfully', JsonArray);
//        Res.Status(200)
//           .ContentType('application/json')
//           .Send<TJSONObject>(ResponseJson);
//      except
//        JsonArray.Free;
//        raise;
//      end;
//    finally
//      Items.Free;
//    end;
//  except
//    on E: Exception do
//      HandleException(E, Res);
//  end;
//end;
//
//procedure TProductController.GetItemById(Req: THorseRequest; Res: THorseResponse);
//var
//  ItemId: Integer;
//  Item: TItem;
//begin
//  try
//    if not TryStrToInt(Req.Params['id'], ItemId) or (ItemId <= 0) then
//      raise EInvalidRequestException.Create('Invalid item ID');
//
//    Item := FProductService.GetItemById(ItemId);
//    if not Assigned(Item) then
//      raise EResourceNotFoundException.Create('Item not found');
//
//    try
//      Res.Status(200)
//         .ContentType('application/json')
//         .Send<TJSONObject>(
//           TJsonResponseHelper.CreateSuccess('Item retrieved successfully',
//             TJSONObject.Create
//               .AddPair('id', TJSONNumber.Create(Item.Id))
//               .AddPair('name', Item.Name)
//               .AddPair('quantity', TJSONNumber.Create(Item.Quantity))
//               .AddPair('price', TJSONNumber.Create(Item.Price))
//           )
//         );
//    finally
//      Item.Free;
//    end;
//  except
//    on E: Exception do
//      HandleException(E, Res);
//  end;
//end;
//
//procedure TProductController.SellItem(Req: THorseRequest; Res: THorseResponse);
//var
//  JsonObj: TJSONObject;
//  ResponseJson: TJSONObject;
//  ItemId, Quantity: Integer;
//  Notification: TStockNotification;
//begin
//  if not GetJsonFromRequest(Req, JsonObj, ResponseJson, Res) then
//    Exit;
//
//  try
//    try
//      if not TryStrToInt(Req.Params['id'], ItemId) or (ItemId <= 0) then
//        raise EInvalidRequestException.Create('Invalid item ID');
//
//      if not JsonObj.TryGetValue<Integer>('quantity', Quantity) then
//        raise EValidationException.Create('Quantity is required');
//
//      if Quantity <= 0 then
//        raise EValidationException.Create('Quantity must be greater than zero');
//
//      Notification := FProductService.SellItem(ItemId, Quantity);
//
//      case Notification of
//        snNone:
//          ResponseJson := TJsonResponseHelper.CreateSuccess('Sale completed successfully');
//        snLowQuantity:
//          ResponseJson := TJsonResponseHelper.CreateSuccess(
//            'Sale completed successfully. Warning: Stock quantity is low',
//            TJSONObject.Create.AddPair('notification', 'Low stock warning'));
//        snCriticalQuantity:
//          ResponseJson := TJsonResponseHelper.CreateSuccess(
//            'Sale completed successfully. Warning: Stock quantity is critical',
//            TJSONObject.Create.AddPair('notification', 'Critical stock warning'));
//      end;
//
//      Res.Status(200)
//         .ContentType('application/json')
//         .Send<TJSONObject>(ResponseJson);
//    except
//      on E: EProductServiceException do
//        raise EValidationException.Create(E.Message);
//    end;
//  except
//    on E: Exception do
//      HandleException(E, Res);
//  end;
//  JsonObj.Free;
//end;
//
//procedure TProductController.GetNotifications(Req: THorseRequest; Res: THorseResponse);
//var
//  Notifications: TObjectList<TNotification>;
//  JsonArray: TJSONArray;
//  ResponseJson: TJSONObject;
//  NotificationTypeStr: string;
//begin
//  try
//    Notifications := FProductService.GetNotifications;
//    try
//      JsonArray := TJSONArray.Create;
//      try
//        for var Notification in Notifications do
//        begin
//          case Notification.NotificationType of
//            ntLowStock: NotificationTypeStr := 'Low Stock';
//            ntCriticalStock: NotificationTypeStr := 'Critical Stock';
//          else
//            NotificationTypeStr := 'Unknown';
//          end;
//
//          JsonArray.AddElement(
//            TJSONObject.Create
//              .AddPair('id', TJSONNumber.Create(Notification.Id))
//              .AddPair('product_id', TJSONNumber.Create(Notification.ProductId))
//              .AddPair('product_name', Notification.ProductName)
//              .AddPair('type', NotificationTypeStr)
//              .AddPair('message', Notification.Message)
//              .AddPair('created_at', DateTimeToStr(Notification.CreatedAt))
//          );
//        end;
//
//        ResponseJson := TJsonResponseHelper.CreateSuccess('Notifications retrieved successfully', JsonArray);
//        Res.Status(200)
//           .ContentType('application/json')
//           .Send<TJSONObject>(ResponseJson);
//      except
//        JsonArray.Free;
//        raise;
//      end;
//    finally
//      Notifications.Free;
//    end;
//  except
//    on E: Exception do
//      HandleException(E, Res);
//  end;
//end;
//
//end.
