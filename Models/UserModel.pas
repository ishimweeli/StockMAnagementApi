unit UserModel;

interface

type
  TUserRole = (urAdmin, urStockOfficer);

  TUser = class
  private
    FId: Integer;
    FUsername: string;
    FPassword: string;
    FRole: TUserRole;
    FEmail: string;
    FCreatedAt: TDateTime;
  public
    property Id: Integer read FId write FId;
    property Username: string read FUsername write FUsername;
    property Password: string read FPassword write FPassword;
    property Role: TUserRole read FRole write FRole;
    property Email: string read FEmail write FEmail;
    property CreatedAt: TDateTime read FCreatedAt write FCreatedAt;
  end;

implementation

end.

