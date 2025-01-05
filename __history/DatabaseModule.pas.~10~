unit DatabaseModule;

interface

uses
  System.SysUtils,
  System.Classes,
  System.Variants,
  FireDAC.Stan.Intf,
  FireDAC.Stan.Option,
  FireDAC.Stan.Error,
  FireDAC.UI.Intf,
  FireDAC.Phys.Intf,
  FireDAC.Stan.Def,
  FireDAC.Stan.Pool,
  FireDAC.Stan.Async,
  FireDAC.Phys,
  FireDAC.Phys.SQLite,
  FireDAC.Phys.SQLiteDef,
  FireDAC.ConsoleUI.Wait,
  FireDAC.Comp.Client,
  FireDAC.Stan.Param,
  FireDAC.DatS,
  FireDAC.DApt.Intf,
  FireDAC.DApt,
  FireDAC.Comp.DataSet;

type
  TNotificationType = (ntLowStock, ntCriticalStock);

  EDatabaseError = class(Exception);

  TDatabaseConnection = class
  private
    FConnection: TFDConnection;
    FQuery: TFDQuery;
    FDatabasePath: string;
    FCurrentSchemaVersion: Integer;
    const LATEST_SCHEMA_VERSION = 2;

    function GetConnected: Boolean;
    procedure InitializeDatabase;
    procedure CreateSchemaVersionTable;
    procedure CheckAndUpdateSchema;
    procedure CreateUsersTable;
    procedure CreateProductsTable;
    procedure CreateNotificationsTable;
    procedure ApplySchemaUpdates(const FromVersion: Integer);
    function GetCurrentSchemaVersion: Integer;
    procedure UpdateSchemaVersion(const NewVersion: Integer);
  protected
    procedure HandleException(const ErrorMsg: string);
  public
    constructor Create(const ADatabasePath: string = 'database.db');
    destructor Destroy; override;

    procedure Connect;
    procedure Disconnect;
    function GetConnection: TFDConnection;
    function CreateQuery: TFDQuery;

    procedure StartTransaction;
    procedure Commit;
    procedure Rollback;

    function ExecuteSQL(const SQL: string): Integer;
    function ExecuteScalar(const SQL: string): Variant;
    function OpenQuery(const SQL: string): TFDQuery;

    property Connected: Boolean read GetConnected;
    property DatabasePath: string read FDatabasePath write FDatabasePath;
  end;

var
  DatabaseModule1: TDatabaseConnection;

implementation

{ TDatabaseConnection }

constructor TDatabaseConnection.Create(const ADatabasePath: string);
begin
  inherited Create;
  try
    FDatabasePath := ADatabasePath;
    FConnection := TFDConnection.Create(nil);
    FConnection.DriverName := 'SQLite';

    with FConnection.Params do
    begin
      Clear;
      Add('DriverID=SQLite');
      Add('Database=' + FDatabasePath);
      Add('LockingMode=Normal');
      Add('JournalMode=WAL');
      Add('ForeignKeys=True');
      Add('StringFormat=Unicode');
    end;

    FQuery := TFDQuery.Create(nil);
    FQuery.Connection := FConnection;

  except
    on E: Exception do
      HandleException('Error creating database connection: ' + E.Message);
  end;
end;

destructor TDatabaseConnection.Destroy;
begin
  try
    if Connected then
      Disconnect;

    if Assigned(FQuery) then
      FQuery.Free;

    if Assigned(FConnection) then
      FConnection.Free;

  finally
    inherited Destroy;
  end;
end;

procedure TDatabaseConnection.CreateSchemaVersionTable;
const
  SQL_CREATE_SCHEMA_VERSION =
    'CREATE TABLE IF NOT EXISTS schema_version (' +
    '  version INTEGER NOT NULL,' +
    '  updated_at DATETIME DEFAULT CURRENT_TIMESTAMP' +
    ');';
begin
  try
    ExecuteSQL(SQL_CREATE_SCHEMA_VERSION);

    // Initialize version if table is empty
    if ExecuteScalar('SELECT COUNT(*) FROM schema_version') = 0 then
    begin
      ExecuteSQL('INSERT INTO schema_version (version) VALUES (1)');
    end;
  except
    on E: Exception do
      HandleException('Error creating schema version table: ' + E.Message);
  end;
end;

function TDatabaseConnection.GetCurrentSchemaVersion: Integer;
begin
  Result := ExecuteScalar('SELECT version FROM schema_version LIMIT 1');
end;

procedure TDatabaseConnection.UpdateSchemaVersion(const NewVersion: Integer);
begin
  ExecuteSQL(Format('UPDATE schema_version SET version = %d, updated_at = CURRENT_TIMESTAMP', [NewVersion]));
end;

procedure TDatabaseConnection.ApplySchemaUpdates(const FromVersion: Integer);
begin
  try
    StartTransaction;
    try
      // Update from version 1 to 2 (adding initial_quantity)
      if FromVersion < 2 then
      begin
        ExecuteSQL('ALTER TABLE products ADD COLUMN initial_quantity INTEGER NOT NULL DEFAULT 0');
        ExecuteSQL('UPDATE products SET initial_quantity = quantity WHERE initial_quantity = 0');
      end;

      // Add more version updates here as needed
      // if FromVersion < 3 then
      // begin
      //   -- Add new schema changes for version 3
      // end;

      UpdateSchemaVersion(LATEST_SCHEMA_VERSION);
      Commit;
    except
      Rollback;
      raise;
    end;
  except
    on E: Exception do
      HandleException('Error applying schema updates: ' + E.Message);
  end;
end;

procedure TDatabaseConnection.CheckAndUpdateSchema;
var
  CurrentVersion: Integer;
begin
  CreateSchemaVersionTable;
  CurrentVersion := GetCurrentSchemaVersion;

  if CurrentVersion < LATEST_SCHEMA_VERSION then
  begin
    ApplySchemaUpdates(CurrentVersion);
  end;
end;

procedure TDatabaseConnection.InitializeDatabase;
begin
  try
    CheckAndUpdateSchema;
    CreateUsersTable;
    CreateProductsTable;
    CreateNotificationsTable;
  except
    on E: Exception do
      HandleException('Error initializing database: ' + E.Message);
  end;
end;

procedure TDatabaseConnection.CreateNotificationsTable;
const
  SQL_CREATE_NOTIFICATIONS_TABLE =
    'CREATE TABLE IF NOT EXISTS notifications (' +
    '  id INTEGER PRIMARY KEY AUTOINCREMENT,' +
    '  product_id INTEGER NOT NULL,' +
    '  product_name VARCHAR(100) NOT NULL,' +
    '  notification_type INTEGER NOT NULL,' + // 0 for LowStock, 1 for CriticalStock
    '  message TEXT NOT NULL,' +
    '  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,' +
    '  FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE' +
    ');' +
    'CREATE INDEX IF NOT EXISTS idx_notifications_product ON notifications(product_id);';
begin
  try
    ExecuteSQL(SQL_CREATE_NOTIFICATIONS_TABLE);
  except
    on E: Exception do
      HandleException('Error creating notifications table: ' + E.Message);
  end;
end;

procedure TDatabaseConnection.CreateUsersTable;
const
  SQL_CREATE_USERS_TABLE =
    'CREATE TABLE IF NOT EXISTS users (' +
    '  id INTEGER PRIMARY KEY AUTOINCREMENT,' +
    '  username VARCHAR(50) NOT NULL UNIQUE,' +
    '  password VARCHAR(255) NOT NULL,' +
    '  role INTEGER NOT NULL,' +  // 0 for Admin, 1 for StockOfficer
    '  email VARCHAR(100) NOT NULL UNIQUE,' +
    '  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,' +
    '  updated_at DATETIME DEFAULT CURRENT_TIMESTAMP' +
    ');' +

    'CREATE INDEX IF NOT EXISTS idx_users_username ON users(username);' +
    'CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);' +

    'CREATE TRIGGER IF NOT EXISTS update_users_timestamp ' +
    'AFTER UPDATE ON users ' +
    'BEGIN ' +
    '  UPDATE users SET updated_at = CURRENT_TIMESTAMP ' +
    '  WHERE id = NEW.id; ' +
    'END;';
begin
  try
    ExecuteSQL(SQL_CREATE_USERS_TABLE);
  except
    on E: Exception do
      HandleException('Error creating users table: ' + E.Message);
  end;
end;

procedure TDatabaseConnection.CreateProductsTable;
const
  SQL_CREATE_PRODUCTS_TABLE =
    'CREATE TABLE IF NOT EXISTS products (' +
    '  id INTEGER PRIMARY KEY AUTOINCREMENT,' +
    '  name VARCHAR(100) NOT NULL,' +
    '  quantity INTEGER NOT NULL DEFAULT 0,' +
    '  price REAL NOT NULL,' +
    '  initial_quantity INTEGER NOT NULL DEFAULT 0,' +
    '  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,' +
    '  updated_at DATETIME DEFAULT CURRENT_TIMESTAMP' +
    ');' +

    'CREATE INDEX IF NOT EXISTS idx_products_name ON products(name);' +

    'CREATE TRIGGER IF NOT EXISTS update_products_timestamp ' +
    'AFTER UPDATE ON products ' +
    'BEGIN ' +
    '  UPDATE products SET updated_at = CURRENT_TIMESTAMP ' +
    '  WHERE id = NEW.id; ' +
    'END;' +

    'CREATE TRIGGER IF NOT EXISTS set_initial_quantity ' +
    'AFTER INSERT ON products ' +
    'BEGIN ' +
    '  UPDATE products SET initial_quantity = NEW.quantity ' +
    '  WHERE id = NEW.id AND initial_quantity = 0; ' +
    'END;';
begin
  try
    ExecuteSQL(SQL_CREATE_PRODUCTS_TABLE);
  except
    on E: Exception do
      HandleException('Error creating products table: ' + E.Message);
  end;
end;

procedure TDatabaseConnection.Connect;
begin
  try
    if not Connected then
    begin
      FConnection.Connected := True;
      InitializeDatabase;
    end;
  except
    on E: Exception do
      HandleException('Error connecting to database: ' + E.Message);
  end;
end;

procedure TDatabaseConnection.Disconnect;
begin
  try
    if Connected then
      FConnection.Connected := False;
  except
    on E: Exception do
      HandleException('Error disconnecting from database: ' + E.Message);
  end;
end;

function TDatabaseConnection.GetConnected: Boolean;
begin
  Result := FConnection.Connected;
end;

function TDatabaseConnection.GetConnection: TFDConnection;
begin
  Result := FConnection;
end;

procedure TDatabaseConnection.HandleException(const ErrorMsg: string);
begin
  raise EDatabaseError.Create(ErrorMsg);
end;

procedure TDatabaseConnection.StartTransaction;
begin
  try
    if not Connected then
      Connect;
    FConnection.StartTransaction;
  except
    on E: Exception do
      HandleException('Error starting transaction: ' + E.Message);
  end;
end;

procedure TDatabaseConnection.Commit;
begin
  try
    FConnection.Commit;
  except
    on E: Exception do
      HandleException('Error committing transaction: ' + E.Message);
  end;
end;

procedure TDatabaseConnection.Rollback;
begin
  try
    FConnection.Rollback;
  except
    on E: Exception do
      HandleException('Error rolling back transaction: ' + E.Message);
  end;
end;

function TDatabaseConnection.CreateQuery: TFDQuery;
begin
  Result := TFDQuery.Create(nil);
  Result.Connection := FConnection;
end;

function TDatabaseConnection.ExecuteSQL(const SQL: string): Integer;
begin
  try
    Result := FConnection.ExecSQL(SQL);
  except
    on E: Exception do
    begin
      HandleException('Error executing SQL: ' + E.Message);
      Result := -1;
    end;
  end;
end;

function TDatabaseConnection.ExecuteScalar(const SQL: string): Variant;
begin
  try
    FQuery.Close;
    FQuery.SQL.Text := SQL;
    FQuery.Open;
    if not FQuery.IsEmpty then
      Result := FQuery.Fields[0].Value
    else
      Result := System.Variants.Null;
    FQuery.Close;
  except
    on E: Exception do
    begin
      HandleException('Error executing scalar query: ' + E.Message);
      Result := System.Variants.Null;
    end;
  end;
end;

function TDatabaseConnection.OpenQuery(const SQL: string): TFDQuery;
begin
  Result := CreateQuery;
  try
    Result.SQL.Text := SQL;
    Result.Open;
  except
    on E: Exception do
    begin
      Result.Free;
      HandleException('Error opening query: ' + E.Message);
    end;
  end;
end;

initialization
  DatabaseModule1 := TDatabaseConnection.Create;

finalization
  DatabaseModule1.Free;

end.
