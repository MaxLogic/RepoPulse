unit UTextDetailsDialog;

interface

uses
  System.Classes, System.Diagnostics, System.ImageList,
  Winapi.Windows,
  Vcl.BaseImageCollection, Vcl.Buttons, Vcl.Clipbrd, Vcl.Controls, Vcl.ExtCtrls,
  Vcl.Forms, Vcl.ImgList, Vcl.StdCtrls, Vcl.VirtualImageList,
  AdvTypes;

type
  TfrmTextDetailsDialog = class(TForm)
    pnlContent: TPanel;
    memDetails: TMemo;
    pnlActions: TPanel;
    btnClose: TBitBtn;
    btnCopy: TBitBtn;
    DialogButtonImages: TVirtualImageList;
    DialogButtonSvgCollection: TAdvSVGImageCollection;
    procedure btnCopyClick(aSender: TObject);
    procedure FormCreate(aSender: TObject);
    procedure FormKeyDown(aSender: TObject; var aKey: Word; aShift: TShiftState);
  private
    procedure CopyToClipboard(const aText: string);
  public
    class procedure ShowDetails(const aCaption, aText: string); static;
  end;

implementation

uses
  AutoFree, UDialogIcons;

{$R *.dfm}

const
  cClipboardRetryDelayMs = 10;
  cClipboardRetryTimeoutMs = 250;

procedure TfrmTextDetailsDialog.btnCopyClick(aSender: TObject);
begin
  CopyToClipboard(memDetails.Text);
end;

procedure TfrmTextDetailsDialog.FormCreate(aSender: TObject);
begin
  ConfigureDialogButtonImages(DialogButtonSvgCollection, DialogButtonImages,
    btnCopy, btnClose);
end;

procedure TfrmTextDetailsDialog.CopyToClipboard(const aText: string);
var
  lStopwatch: TStopwatch;
begin
  lStopwatch := TStopwatch.StartNew;
  repeat
    try
      Clipboard.AsText := aText;
      Exit;
    except
      on EClipboardException do
      begin
        if lStopwatch.ElapsedMilliseconds >= cClipboardRetryTimeoutMs then
          raise;
      end;
    end;
    TThread.Sleep(cClipboardRetryDelayMs);
  until False;
end;

procedure TfrmTextDetailsDialog.FormKeyDown(aSender: TObject; var aKey: Word;
  aShift: TShiftState);
begin
  if aKey = VK_ESCAPE then
  begin
    aKey := 0;
    ModalResult := mrCancel;
  end;
end;

class procedure TfrmTextDetailsDialog.ShowDetails(const aCaption, aText: string);
var
  g: TGarbos;
  lDialog: TfrmTextDetailsDialog;
begin
  GC(lDialog, TfrmTextDetailsDialog.Create(nil), g);
  lDialog.Caption := aCaption;
  lDialog.memDetails.Text := aText;
  lDialog.ShowModal;
end;

initialization
  System.Classes.RegisterClass(TfrmTextDetailsDialog);

finalization
  System.Classes.UnRegisterClass(TfrmTextDetailsDialog);

end.
