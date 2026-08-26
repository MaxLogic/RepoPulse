unit UScanPathsDialog;

interface

uses
  System.Classes,

  Vcl.Controls, Vcl.Dialogs, Vcl.ExtCtrls, Vcl.Forms, Vcl.StdCtrls,
  UEscapeDialog;

type
  TfrmScanPathsDialog = class(TEscapeDialogForm)
    memPaths: TMemo;
    lblInstructions: TStaticText;
    pnlActions: TPanel;
    btnAddFolder: TButton;
    btnCancel: TButton;
    btnOk: TButton;
    procedure btnAddFolderClick(Sender: TObject);
    procedure btnOkClick(Sender: TObject);
  private
    fNormalizedPaths: TArray<string>;
  public
    class function Execute(const aOwner: TComponent; const aCurrentPaths: TArray<string>;
      out aPaths: TArray<string>): Boolean; static;
  end;

implementation

uses
  System.SysUtils,

  UScanPaths;

{$R *.dfm}

resourcestring
  rsAddScanFolder = 'Add Scan Folder';

procedure TfrmScanPathsDialog.btnAddFolderClick(Sender: TObject);
var
  lDialog: TFileOpenDialog;
  lDefaultFolder: string;
begin
  lDialog := TFileOpenDialog.Create(Self);
  try
    lDialog.Options := lDialog.Options + [fdoPickFolders];
    lDialog.Title := rsAddScanFolder;
    if memPaths.Lines.Count > 0 then
    begin
      lDefaultFolder := Trim(memPaths.Lines[0]);
      if DirectoryExists(lDefaultFolder) then
        lDialog.DefaultFolder := lDefaultFolder;
    end;
    if lDialog.Execute then
      memPaths.Lines.Add(lDialog.FileName);
  finally
    lDialog.Free;
  end;
end;

procedure TfrmScanPathsDialog.btnOkClick(Sender: TObject);
var
  lError: string;
begin
  if not TryNormalizeScanPaths(memPaths.Lines, fNormalizedPaths, lError) then
  begin
    MessageDlg(lError, mtError, [mbOk], 0);
    memPaths.SetFocus;
    Exit;
  end;
  ModalResult := mrOk;
end;

class function TfrmScanPathsDialog.Execute(const aOwner: TComponent;
  const aCurrentPaths: TArray<string>; out aPaths: TArray<string>): Boolean;
var
  lForm: TfrmScanPathsDialog;
  lPath: string;
begin
  aPaths := [];
  lForm := TfrmScanPathsDialog.Create(aOwner);
  try
    lForm.memPaths.Lines.BeginUpdate;
    try
      lForm.memPaths.Clear;
      for lPath in aCurrentPaths do
        lForm.memPaths.Lines.Add(lPath);
    finally
      lForm.memPaths.Lines.EndUpdate;
    end;
    lForm.ActiveControl := lForm.memPaths;
    Result := lForm.ShowModal = mrOk;
    if Result then
      aPaths := Copy(lForm.fNormalizedPaths);
  finally
    lForm.Free;
  end;
end;

end.
