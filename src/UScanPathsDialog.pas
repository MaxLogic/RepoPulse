unit UScanPathsDialog;

interface

uses
  System.Classes,

  Vcl.Buttons, Vcl.Controls, Vcl.Dialogs, Vcl.ExtCtrls, Vcl.Forms, Vcl.StdCtrls,
  UEscapeDialog;

function TryLoadIgnoreRules(const aPath: string; const aDefaults: TArray<string>;
  const aLines: TStrings; out aError: string): Boolean;
function TrySaveIgnoreRules(const aPath: string; const aLines: TStrings;
  out aError: string): Boolean;

type
  TfrmScanPathsDialog = class(TEscapeDialogForm)
    pnlScanPaths: TPanel;
    memPaths: TMemo;
    lblInstructions: TStaticText;
    pnlIgnorePaths: TPanel;
    memIgnorePaths: TMemo;
    lblIgnorePaths: TStaticText;
    pnlActions: TPanel;
    btnAddFolder: TBitBtn;
    btnCancel: TBitBtn;
    btnOk: TBitBtn;
    procedure btnAddFolderClick(Sender: TObject);
    procedure btnOkClick(Sender: TObject);
  private
    fNormalizedPaths: TArray<string>;
    fTraversalOnly: Boolean;
  protected
    fIgnorePath: string;
  public
    procedure ConfigureTraversalOnly;
    class function ExecuteTraversalOptions(const aOwner: TComponent;
      const aIgnorePath: string; const aDefaultIgnoreRules: TArray<string>): Boolean; static;
    class function Execute(const aOwner: TComponent; const aCurrentPaths: TArray<string>;
      out aPaths: TArray<string>): Boolean; overload; static;
    class function Execute(const aOwner: TComponent; const aCurrentPaths: TArray<string>;
      const aIgnorePath: string; const aDefaultIgnoreRules: TArray<string>;
      out aPaths: TArray<string>): Boolean; overload; static;
  end;

implementation

uses
  System.SysUtils,

  UScanPaths;

{$R *.dfm}

resourcestring
  rsAddScanFolder = 'Add Scan Folder';
  rsIgnoreLoadFailed = 'Failed to load ignore rules file: ';
  rsIgnoreSaveFailed = 'Failed to save ignore rules file: ';
  rsTraversalOptions = 'Traversal Options';

procedure TfrmScanPathsDialog.ConfigureTraversalOnly;
begin
  fTraversalOnly := True;
  Caption := rsTraversalOptions;
  pnlScanPaths.Visible := False;
  btnAddFolder.Visible := False;
  ActiveControl := memIgnorePaths;
end;

class function TfrmScanPathsDialog.ExecuteTraversalOptions(const aOwner: TComponent;
  const aIgnorePath: string; const aDefaultIgnoreRules: TArray<string>): Boolean;
var
  lForm: TfrmScanPathsDialog;
  lError: string;
begin
  lForm := TfrmScanPathsDialog.Create(aOwner);
  try
    lForm.ConfigureTraversalOnly;
    lForm.fIgnorePath := aIgnorePath;
    if not TryLoadIgnoreRules(aIgnorePath, aDefaultIgnoreRules,
      lForm.memIgnorePaths.Lines, lError) then
    begin
      MessageDlg(lError, mtError, [mbOk], 0);
      Exit(False);
    end;
    Result := lForm.ShowModal = mrOk;
  finally
    lForm.Free;
  end;
end;

function TryLoadIgnoreRules(const aPath: string; const aDefaults: TArray<string>;
  const aLines: TStrings; out aError: string): Boolean;
var
  lDefault: string;
begin
  aError := '';
  aLines.BeginUpdate;
  try
    aLines.Clear;
    try
      if FileExists(aPath) then
        aLines.LoadFromFile(aPath, TEncoding.UTF8)
      else
        for lDefault in aDefaults do
          aLines.Add(lDefault);
      Result := True;
    except
      on E: Exception do
      begin
        aError := rsIgnoreLoadFailed + E.Message;
        Result := False;
      end;
    end;
  finally
    aLines.EndUpdate;
  end;
end;

function TrySaveIgnoreRules(const aPath: string; const aLines: TStrings;
  out aError: string): Boolean;
var
  lFolder: string;
begin
  aError := '';
  try
    lFolder := ExcludeTrailingPathDelimiter(ExtractFilePath(aPath));
    if (lFolder <> '') and (not DirectoryExists(lFolder)) then
      ForceDirectories(lFolder);
    aLines.SaveToFile(aPath, TEncoding.UTF8);
    Result := True;
  except
    on E: Exception do
    begin
      aError := rsIgnoreSaveFailed + E.Message;
      Result := False;
    end;
  end;
end;

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
  if not fTraversalOnly and
    not TryNormalizeScanPaths(memPaths.Lines, fNormalizedPaths, lError) then
  begin
    MessageDlg(lError, mtError, [mbOk], 0);
    memPaths.SetFocus;
    Exit;
  end;
  if (fIgnorePath <> '') and (not TrySaveIgnoreRules(fIgnorePath, memIgnorePaths.Lines, lError)) then
  begin
    MessageDlg(lError, mtError, [mbOk], 0);
    memIgnorePaths.SetFocus;
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

class function TfrmScanPathsDialog.Execute(const aOwner: TComponent;
  const aCurrentPaths: TArray<string>; const aIgnorePath: string;
  const aDefaultIgnoreRules: TArray<string>; out aPaths: TArray<string>): Boolean;
var
  lForm: TfrmScanPathsDialog;
  lPath: string;
  lError: string;
begin
  aPaths := [];
  lForm := TfrmScanPathsDialog.Create(aOwner);
  try
    lForm.fIgnorePath := aIgnorePath;
    if not TryLoadIgnoreRules(aIgnorePath, aDefaultIgnoreRules, lForm.memIgnorePaths.Lines,
      lError) then
    begin
      MessageDlg(lError, mtError, [mbOk], 0);
      Exit(False);
    end;
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
