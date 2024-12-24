unit ProductModel;

interface

type
  TItem = class
  private
    FId: Integer;
    FName: string;
    FQuantity: Integer;
    FPrice: Double;
    FInitialQuantity: Integer;
  public
    property Id: Integer read FId write FId;
    property Name: string read FName write FName;
    property Quantity: Integer read FQuantity write FQuantity;
    property Price: Double read FPrice write FPrice;
    property InitialQuantity: Integer read FInitialQuantity write FInitialQuantity;
  end;

implementation

end.
