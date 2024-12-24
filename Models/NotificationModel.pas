unit NotificationModel;

interface

uses
  System.SysUtils;

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

implementation

end.
