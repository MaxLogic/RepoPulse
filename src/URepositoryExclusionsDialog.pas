unit URepositoryExclusionsDialog;

interface

uses
  System.Classes, System.SysUtils,
  Vcl.Buttons, Vcl.Controls, Vcl.ExtCtrls, Vcl.Forms, Vcl.StdCtrls,
  UEscapeDialog, URepoListModel;

type
  TRepositoryExclusionsDialog = class(TEscapeDialogForm)
    pnlRules: TPanel;
    memPatterns: TMemo;
    lblPatterns: TStaticText;
    lblHelp: TStaticText;
    pnlPreview: TPanel;
    lstPreview: TListBox;
    lblPreview: TStaticText;
    pnlActions: TPanel;
    btnCancel: TBitBtn;
    btnApply: TBitBtn;
    procedure memPatternsChange(Sender: TObject);
  private
    fModel: TRepoListModel;
    procedure UpdatePreview;
  public
    procedure Initialize(const aModel: TRepoListModel; const aPatterns: TArray<string>);
    function Patterns: TArray<string>;
  end;

implementation

{$R *.dfm}

resourcestring
  rsPreviewCount = '&Preview: %d known repositories would be hidden';

procedure TRepositoryExclusionsDialog.Initialize(const aModel: TRepoListModel;
  const aPatterns: TArray<string>);
begin
  fModel := aModel;
  memPatterns.Lines.BeginUpdate;
  try
    memPatterns.Lines.Clear;
    memPatterns.Lines.AddStrings(aPatterns);
  finally
    memPatterns.Lines.EndUpdate;
  end;
  UpdatePreview;
  ActiveControl := memPatterns;
end;

procedure TRepositoryExclusionsDialog.memPatternsChange(Sender: TObject);
begin
  UpdatePreview;
end;

procedure TRepositoryExclusionsDialog.UpdatePreview;
var
  lRoots: TArray<string>;
begin
  lRoots := [];
  if Assigned(fModel) then
    lRoots := fModel.PreviewExcludedRoots(Patterns);
  lstPreview.Items.BeginUpdate;
  try
    lstPreview.Items.Clear;
    lstPreview.Items.AddStrings(lRoots);
  finally
    lstPreview.Items.EndUpdate;
  end;
  lblPreview.Caption := Format(rsPreviewCount, [Length(lRoots)]);
end;

function TRepositoryExclusionsDialog.Patterns: TArray<string>;
var
  i, lCount: Integer;
  lPattern: string;
begin
  SetLength(Result, memPatterns.Lines.Count);
  lCount := 0;
  for i := 0 to memPatterns.Lines.Count - 1 do
  begin
    lPattern := memPatterns.Lines[i];
    if Trim(lPattern) <> '' then
    begin
      Result[lCount] := lPattern;
      Inc(lCount);
    end;
  end;
  SetLength(Result, lCount);
end;

end.
