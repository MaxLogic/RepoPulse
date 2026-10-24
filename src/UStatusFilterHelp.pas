unit UStatusFilterHelp;

interface

uses
  System.Classes, System.ImageList,
  Winapi.Windows,
  Vcl.BaseImageCollection, Vcl.Buttons, Vcl.Controls, Vcl.ExtCtrls, Vcl.Forms,
  Vcl.ImgList, Vcl.StdCtrls, Vcl.VirtualImageList,
  AdvTypes;

type
  TfrmStatusFilterHelp = class(TForm)
    pnlContent: TPanel;
    memStatusFilterHelp: TMemo;
    pnlActions: TPanel;
    btnClose: TBitBtn;
    DialogButtonImages: TVirtualImageList;
    DialogButtonSvgCollection: TAdvSVGImageCollection;
    procedure FormCreate(aSender: TObject);
    procedure FormKeyDown(aSender: TObject; var aKey: Word; aShift: TShiftState);
  end;

implementation

uses
  UDialogIcons;

{$R *.dfm}

procedure TfrmStatusFilterHelp.FormCreate(aSender: TObject);
begin
  ConfigureDialogButtonImages(DialogButtonSvgCollection, DialogButtonImages,
    nil, btnClose);
end;

procedure TfrmStatusFilterHelp.FormKeyDown(aSender: TObject; var aKey: Word;
  aShift: TShiftState);
begin
  if aKey = VK_ESCAPE then
  begin
    aKey := 0;
    ModalResult := mrCancel;
  end;
end;

initialization
  System.Classes.RegisterClass(TfrmStatusFilterHelp);

finalization
  System.Classes.UnRegisterClass(TfrmStatusFilterHelp);

end.
