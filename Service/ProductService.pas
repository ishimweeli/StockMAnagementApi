unit ProductService;

interface

uses
  ProductModel,
  DatabaseModule,
  System.SysUtils,
  System.Generics.Collections,
  FireDAC.Comp.Client,
  FireDAC.Stan.Param;

type
  TNotificationType = (ntLowStock, ntCriticalStock);

  TNotification = class
  private
    FId: Integer;
    FProductId: Integer;
    FProductName: string;
    FNotificationType: TNotificationType;
    FMessage: string;
    FCreatedAt: TDateTime;
  public
    property Id: Integer read FId write FId;
    property ProductId: Integer read FProductId write FProductId;
    property ProductName: string read FProductName write FProductName;
    property NotificationType: TNotificationType read FNotificationType write FNotificationType;
    property Message: string read FMessage write FMessage;
    property CreatedAt: TDateTime read FCreatedAt write FCreatedAt;
  end;

  TStockNotification = (snNone, snLowQuantity, snCriticalQuantity);

  EProductServiceError = class(Exception);

  TProductService = class
  private
    function CheckQuantityStatus(const CurrentQuantity, InitialQuantity: Integer): TStockNotification;
    function ItemExists(const ItemId: Integer; out CurrentQuantity: Integer;
      out InitialQuantity: Integer): Boolean;
    procedure CreateNotification(const ItemId: Integer; const ItemName: string;
      const NotificationType: TNotificationType; const Message: string);
    function GetInitialQuantity(const ItemId: Integer): Integer;
  public
    function AddItem(const Item: TItem): Boolean;
    function UpdateItem(const ItemId: Integer; const Item: TItem): Boolean;
    function DeleteItem(const ItemId: Integer): Boolean;
    function SellItem(const ItemId: Integer; const Quantity: Integer): TStockNotification;
    function GetAllItems: TObjectList<TItem>;
    function GetItemById(const ItemId: Integer): TItem;
    function GetNotifications: TObjectList<TNotification>;
  end;

implementation

function TProductService.ItemExists(const ItemId: Integer; out CurrentQuantity: Integer;
  out InitialQuantity: Integer): Boolean;
var
  Query: TFDQuery;
begin
  Result := False;
  CurrentQuantity := 0;
  InitialQuantity := 0;

  if ItemId <= 0 then
    Exit;

  Query := DatabaseModule1.CreateQuery;
  try
    try
      Query.SQL.Text :=
        'SELECT quantity, initial_quantity FROM products WHERE id = :id';
      Query.ParamByName('id').AsInteger := ItemId;
      Query.Open;

      if not Query.IsEmpty then
      begin
        Result := True;
        CurrentQuantity := Query.FieldByName('quantity').AsInteger;
        InitialQuantity := Query.FieldByName('initial_quantity').AsInteger;
      end;
    except
      on E: Exception do
        raise EProductServiceError.CreateFmt('Error checking item existence: %s', [E.Message]);
    end;
  finally
    Query.Free;
  end;
end;

function TProductService.GetInitialQuantity(const ItemId: Integer): Integer;
var
  Query: TFDQuery;
begin
  Result := 0;

  if ItemId <= 0 then
    Exit;

  Query := DatabaseModule1.CreateQuery;
  try
    try
      Query.SQL.Text := 'SELECT initial_quantity FROM products WHERE id = :id';
      Query.ParamByName('id').AsInteger := ItemId;
      Query.Open;
      if not Query.IsEmpty then
        Result := Query.FieldByName('initial_quantity').AsInteger;
    except
      on E: Exception do
        raise EProductServiceError.CreateFmt('Error getting initial quantity: %s', [E.Message]);
    end;
  finally
    Query.Free;
  end;
end;

function TProductService.CheckQuantityStatus(const CurrentQuantity, InitialQuantity: Integer): TStockNotification;
var
  Percentage: Double;
begin
  Result := snNone;

  if (CurrentQuantity < 0) or (InitialQuantity <= 0) then
    Exit;

  try
    Percentage := (CurrentQuantity / InitialQuantity) * 100;

    if Percentage <= 5 then
      Result := snCriticalQuantity
    else if Percentage <= 25 then
      Result := snLowQuantity;
  except
    on E: Exception do
      raise EProductServiceError.CreateFmt('Error checking quantity status: %s', [E.Message]);
  end;
end;

procedure TProductService.CreateNotification(const ItemId: Integer; const ItemName: string;
  const NotificationType: TNotificationType; const Message: string);
var
  Query: TFDQuery;
begin
  if (ItemId <= 0) or (ItemName.Trim.IsEmpty) then
    Exit;

  Query := DatabaseModule1.CreateQuery;
  try
    try
      Query.SQL.Text :=
        'INSERT INTO notifications (product_id, product_name, notification_type, message, created_at) ' +
        'VALUES (:product_id, :product_name, :notification_type, :message, :created_at)';
      Query.ParamByName('product_id').AsInteger := ItemId;
      Query.ParamByName('product_name').AsString := ItemName;
      Query.ParamByName('notification_type').AsInteger := Ord(NotificationType);
      Query.ParamByName('message').AsString := Message;
      Query.ParamByName('created_at').AsDateTime := Now;
      Query.ExecSQL;
    except
      on E: Exception do
        raise EProductServiceError.CreateFmt('Error creating notification: %s', [E.Message]);
    end;
  finally
    Query.Free;
  end;
end;

function TProductService.AddItem(const Item: TItem): Boolean;
var
  Query: TFDQuery;
begin
  Result := False;

  // Validate input parameters
  if not Assigned(Item) then
    raise EProductServiceError.Create('Item cannot be nil');
  if Item.Quantity < 0 then
    raise EProductServiceError.Create('Quantity cannot be negative');
  if Item.Price <= 0 then
    raise EProductServiceError.Create('Price must be greater than zero');
  if Item.Name.Trim.IsEmpty then
    raise EProductServiceError.Create('Item name cannot be empty');

  Query := DatabaseModule1.CreateQuery;
  try
    DatabaseModule1.StartTransaction;
    try
      Query.SQL.Text :=
        'INSERT INTO products (name, quantity, price, initial_quantity) ' +
        'VALUES (:name, :quantity, :price, :initial_quantity)';
      Query.ParamByName('name').AsString := Item.Name;
      Query.ParamByName('quantity').AsInteger := Item.Quantity;
      Query.ParamByName('price').AsFloat := Item.Price;
      Query.ParamByName('initial_quantity').AsInteger := Item.Quantity;
      Query.ExecSQL;
      DatabaseModule1.Commit;
      Result := True;
    except
      on E: Exception do
      begin
        DatabaseModule1.Rollback;
        raise EProductServiceError.CreateFmt('Error adding item: %s', [E.Message]);
      end;
    end;
  finally
    Query.Free;
  end;
end;



function TProductService.UpdateItem(const ItemId: Integer; const Item: TItem): Boolean;
var
  Query: TFDQuery;
  CurrentQuantity, InitialQuantity: Integer;
  NotificationStatus: TStockNotification;
begin
  Result := False;

  // Input validation
  if not Assigned(Item) then
    raise EProductServiceError.Create('Item cannot be nil');
  if not ItemExists(ItemId, CurrentQuantity, InitialQuantity) then
    raise EProductServiceError.Create('Item not found');
  if Item.Quantity < 0 then
    raise EProductServiceError.Create('Quantity cannot be negative');
  if Item.Price <= 0 then
    raise EProductServiceError.Create('Price must be greater than zero');
  if Item.Name.Trim.IsEmpty then
    raise EProductServiceError.Create('Item name cannot be empty');

  Query := DatabaseModule1.CreateQuery;
  try
    DatabaseModule1.StartTransaction;
    try
      // Update product details
      Query.SQL.Text := 'UPDATE products SET name = :name, quantity = :quantity, price = :price WHERE id = :id';
      Query.ParamByName('name').AsString := Item.Name;
      Query.ParamByName('quantity').AsInteger := Item.Quantity;
      Query.ParamByName('price').AsFloat := Item.Price;
      Query.ParamByName('id').AsInteger := ItemId;
      Query.ExecSQL;

      // Handle quantity notifications if quantity has changed
      if Item.Quantity <> CurrentQuantity then
      begin
        NotificationStatus := CheckQuantityStatus(Item.Quantity, InitialQuantity);
        case NotificationStatus of
          snLowQuantity:
            CreateNotification(ItemId, Item.Name, ntLowStock,
              Format('Product "%s" quantity less than a quarter of initial stock (%d%%)',
                [Item.Name, Round((Item.Quantity / InitialQuantity) * 100)]));
          snCriticalQuantity:
            CreateNotification(ItemId, Item.Name, ntCriticalStock,
              Format('Product "%s" quantity nearing zero (%d%%)',
                [Item.Name, Round((Item.Quantity / InitialQuantity) * 100)]));
          // snNone requires no action
        end;
      end;

      DatabaseModule1.Commit;
      Result := True;
    except
      on E: Exception do
      begin
        DatabaseModule1.Rollback;
        raise EProductServiceError.CreateFmt('Error updating item: %s', [E.Message]);
      end;
    end;
  finally
    Query.Free;
  end;
end;
function TProductService.DeleteItem(const ItemId: Integer): Boolean;
var
  Query: TFDQuery;
  CurrentQuantity, InitialQuantity: Integer;
begin
  Result := False;

  // Validate item exists
  if not ItemExists(ItemId, CurrentQuantity, InitialQuantity) then
    raise EProductServiceError.Create('Item not found');

  Query := DatabaseModule1.CreateQuery;
  try
    DatabaseModule1.StartTransaction;
    try
      Query.SQL.Text := 'DELETE FROM products WHERE id = :id';
      Query.ParamByName('id').AsInteger := ItemId;
      Query.ExecSQL;

      DatabaseModule1.Commit;
      Result := True;
    except
      on E: Exception do
      begin
        DatabaseModule1.Rollback;
        raise EProductServiceError.CreateFmt('Error deleting item: %s', [E.Message]);
      end;
    end;
  finally
    Query.Free;
  end;
end;


function TProductService.SellItem(const ItemId: Integer; const Quantity: Integer): TStockNotification;
var
  Query: TFDQuery;
  CurrentQuantity, InitialQuantity: Integer;
  Item: TItem;
  NewQuantity: Integer;
begin
  Result := snNone;

  // Input validation
  if Quantity <= 0 then
    raise EProductServiceError.Create('Quantity must be greater than zero');
  if not ItemExists(ItemId, CurrentQuantity, InitialQuantity) then
    raise EProductServiceError.Create('Item not found');
  if CurrentQuantity < Quantity then
    raise EProductServiceError.Create('Insufficient stock');

  Item := GetItemById(ItemId);
  if not Assigned(Item) then
    raise EProductServiceError.Create('Error retrieving item details');

  try
    Query := DatabaseModule1.CreateQuery;
    try
      DatabaseModule1.StartTransaction;
      try
        // Update stock quantity
        Query.SQL.Text := 'UPDATE products SET quantity = quantity - :sold WHERE id = :id';
        Query.ParamByName('sold').AsInteger := Quantity;
        Query.ParamByName('id').AsInteger := ItemId;
        Query.ExecSQL;

        NewQuantity := CurrentQuantity - Quantity;
        Result := CheckQuantityStatus(NewQuantity, InitialQuantity);

        // Create notifications based on new stock levels
        case Result of
          snLowQuantity:
            CreateNotification(ItemId, Item.Name, ntLowStock,
              Format('Product "%s" quantity less than a quarter      (%d%%)',
                [Item.Name, Round((NewQuantity / InitialQuantity) * 100)]));
          snCriticalQuantity:
            CreateNotification(ItemId, Item.Name, ntCriticalStock,
              Format('Product "%s" quantity nearing zero   (%d%%)',
                [Item.Name, Round((NewQuantity / InitialQuantity) * 100)]));
        end;

        DatabaseModule1.Commit;
      except
        on E: Exception do
        begin
          DatabaseModule1.Rollback;
          raise EProductServiceError.CreateFmt('Error selling item: %s', [E.Message]);
        end;
      end;
    finally
      Query.Free;
    end;
  finally
    Item.Free;
  end;
end;

function TProductService.GetAllItems: TObjectList<TItem>;
var
  Query: TFDQuery;
  Item: TItem;
begin
  Result := TObjectList<TItem>.Create(True);
  Query := DatabaseModule1.CreateQuery;
  try
    try
      Query.SQL.Text :=
        'SELECT id, name, quantity, price, initial_quantity ' +
        'FROM products ORDER BY name';
      Query.Open;

      while not Query.Eof do
      begin
        Item := TItem.Create;
        try
          Item.Id := Query.FieldByName('id').AsInteger;
          Item.Name := Query.FieldByName('name').AsString;
          Item.Quantity := Query.FieldByName('quantity').AsInteger;
          Item.Price := Query.FieldByName('price').AsFloat;
          Item.InitialQuantity := Query.FieldByName('initial_quantity').AsInteger;
          Result.Add(Item);
        except
          Item.Free;
          raise;
        end;
        Query.Next;
      end;
    except
      on E: Exception do
      begin
        FreeAndNil(Result);
        raise EProductServiceError.CreateFmt('Error retrieving items: %s', [E.Message]);
      end;
    end;
  finally
    Query.Free;
  end;
end;

function TProductService.GetItemById(const ItemId: Integer): TItem;
var
  Query: TFDQuery;
begin
  Result := nil;

  if ItemId <= 0 then
    Exit;

  Query := DatabaseModule1.CreateQuery;
  try
    try
      Query.SQL.Text :=
        'SELECT id, name, quantity, price, initial_quantity ' +
        'FROM products WHERE id = :id';
      Query.ParamByName('id').AsInteger := ItemId;
      Query.Open;

      if not Query.IsEmpty then
      begin
        Result := TItem.Create;
        try
          Result.Id := Query.FieldByName('id').AsInteger;
          Result.Name := Query.FieldByName('name').AsString;
          Result.Quantity := Query.FieldByName('quantity').AsInteger;
          Result.Price := Query.FieldByName('price').AsFloat;
          Result.InitialQuantity := Query.FieldByName('initial_quantity').AsInteger;
        except
          FreeAndNil(Result);
          raise;
        end;
      end;
    except
      on E: Exception do
      begin
        FreeAndNil(Result);
        raise EProductServiceError.CreateFmt('Error retrieving item: %s', [E.Message]);
      end;
    end;
  finally
    Query.Free;
  end;
end;

function TProductService.GetNotifications: TObjectList<TNotification>;
var
  Query: TFDQuery;
  Notification: TNotification;
begin
  Result := TObjectList<TNotification>.Create(True);
  Query := DatabaseModule1.CreateQuery;
  try
    try
      Query.SQL.Text :=
        'SELECT n.id, n.product_id, n.product_name, n.notification_type, ' +
        'n.message, n.created_at, p.name as product_name ' +
        'FROM notifications n ' +
        'LEFT JOIN products p ON n.product_id = p.id ' +
        'ORDER BY n.created_at DESC';
      Query.Open;

      while not Query.Eof do
      begin
        Notification := TNotification.Create;
        try
          Notification.Id := Query.FieldByName('id').AsInteger;
          Notification.ProductId := Query.FieldByName('product_id').AsInteger;
          Notification.ProductName := Query.FieldByName('product_name').AsString;
          Notification.NotificationType := TNotificationType(Query.FieldByName('notification_type').AsInteger);
          Notification.Message := Query.FieldByName('message').AsString;
          Notification.CreatedAt := Query.FieldByName('created_at').AsDateTime;
          Result.Add(Notification);
        except
          Notification.Free;
          raise;
        end;
        Query.Next;
      end;
    except
      on E: Exception do
      begin
        FreeAndNil(Result);
        raise EProductServiceError.CreateFmt('Error retrieving notifications: %s', [E.Message]);
      end;
    end;
  finally
    Query.Free;
  end;
end;

end.
