unit TestRepositoryExclusionsDialog;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TRepositoryExclusionsDialogTests = class
  public
    [Test]
    procedure Initialize_LoadsExactPatternsAndPreview;
    [Test]
    procedure Editing_RefreshesPreviewWithoutApplyingRules;
    [Test]
    procedure Patterns_IgnoreBlankLinesAndPreserveLiteralSpelling;
  end;

implementation

uses
  System.UITypes,
  Vcl.Forms,
  AutoFree,
  URepositoryExclusionsDialog, URepoListModel;

procedure TRepositoryExclusionsDialogTests.Initialize_LoadsExactPatternsAndPreview;
var
  g: TGarbos;
  lDialog: TRepositoryExclusionsDialog;
  lModel: TRepoListModel;
begin
  GC(lModel, TRepoListModel.Create, g);
  lModel.AddWaiting('C:\Repos\Alpha-workspace', 'Alpha-workspace');
  lModel.AddWaiting('C:\Repos\Beta', 'Beta');
  GC(lDialog, TRepositoryExclusionsDialog.Create(nil), g);
  lDialog.Initialize(lModel, ['*-workspace']);
  Assert.AreEqual(1, lDialog.memPatterns.Lines.Count);
  Assert.AreEqual('*-workspace', lDialog.memPatterns.Lines[0]);
  Assert.AreEqual(1, lDialog.lstPreview.Items.Count);
  Assert.AreEqual('C:\Repos\Alpha-workspace', lDialog.lstPreview.Items[0]);
  Assert.IsTrue(Pos('1 known', lDialog.lblPreview.Caption) > 0);
  Assert.IsTrue(lDialog.ActiveControl = lDialog.memPatterns);
  Assert.AreEqual(2, lModel.VisibleCount);
end;

procedure TRepositoryExclusionsDialogTests.Editing_RefreshesPreviewWithoutApplyingRules;
var
  g: TGarbos;
  lDialog: TRepositoryExclusionsDialog;
  lModel: TRepoListModel;
begin
  GC(lModel, TRepoListModel.Create, g);
  lModel.AddWaiting('C:\Repos\Alpha-workspace', 'Alpha-workspace');
  lModel.AddWaiting('C:\Repos\Beta', 'Beta');
  lModel.SetExclusions(['Beta']);
  GC(lDialog, TRepositoryExclusionsDialog.Create(nil), g);
  lDialog.Initialize(lModel, ['Beta']);
  lDialog.memPatterns.Text := '*-workspace';
  Assert.AreEqual(1, lDialog.lstPreview.Items.Count);
  Assert.AreEqual('C:\Repos\Alpha-workspace', lDialog.lstPreview.Items[0]);
  Assert.AreEqual('C:\Repos\Alpha-workspace', lModel.ItemAtVisible(0).RepoRoot);
  lDialog.memPatterns.SelectAll;
  lDialog.memPatterns.ClearSelection;
  Assert.AreEqual('', lDialog.memPatterns.Text);
  Assert.AreEqual(0, lDialog.lstPreview.Items.Count);
  Assert.IsTrue(Pos('0 known', lDialog.lblPreview.Caption) > 0);
  lDialog.btnCancel.Click;
  Assert.AreEqual(Integer(mrCancel), Integer(lDialog.ModalResult));
  Assert.AreEqual(1, lModel.VisibleCount);
end;

procedure TRepositoryExclusionsDialogTests.Patterns_IgnoreBlankLinesAndPreserveLiteralSpelling;
var
  g: TGarbos;
  lDialog: TRepositoryExclusionsDialog;
  lPatterns: TArray<string>;
begin
  GC(lDialog, TRepositoryExclusionsDialog.Create(nil), g);
  lDialog.memPatterns.Text := #13#10'   '#13#10'*\_obselete\*'#13#10 +
    '\\Server\Share\Repo,Archive*'#13#10'#literal'#13#10'!literal'#13#10' Spaced* '#13#10;
  lPatterns := lDialog.Patterns;
  Assert.AreEqual(5, Length(lPatterns));
  Assert.AreEqual('*\_obselete\*', lPatterns[0]);
  Assert.AreEqual('\\Server\Share\Repo,Archive*', lPatterns[1]);
  Assert.AreEqual('#literal', lPatterns[2]);
  Assert.AreEqual('!literal', lPatterns[3]);
  Assert.AreEqual(' Spaced* ', lPatterns[4]);
  lDialog.btnApply.Click;
  Assert.AreEqual(Integer(mrOk), Integer(lDialog.ModalResult));
end;

initialization
  TDUnitX.RegisterTestFixture(TRepositoryExclusionsDialogTests);

end.
