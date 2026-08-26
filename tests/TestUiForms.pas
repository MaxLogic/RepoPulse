unit TestUiForms;

interface

uses
  System.Classes,
  Winapi.Windows,
  Vcl.Controls, Vcl.Forms,
  VirtualTrees.Types,
  DUnitX.TestFramework,
  UMainForm, UScanPathsDialog;

type
  TTestScanPathsDialog = class(TfrmScanPathsDialog)
  public
    procedure SendKey(const aKey: Word);
  end;

  [TestFixture]
  TUiFormTests = class
  public
    [Test]
    procedure Toolbar_ScanIsLeftmostAction;
    [Test]
    procedure Toolbar_AllActionsHaveDistinctSvgImages;
    [Test]
    procedure ScanActivity_UsesSkillSearchAnimatedControl;
    [Test]
    procedure ScanPathsDialog_EscapeCancels;
    [Test]
    procedure RepositoryView_UsesVirtualStringTree;
  end;

implementation

procedure TTestScanPathsDialog.SendKey(const aKey: Word);
var
  lKey: Word;
begin
  lKey := aKey;
  KeyDown(lKey, []);
end;

procedure TUiFormTests.Toolbar_ScanIsLeftmostAction;
var
  lForm: TfrmMain;
begin
  lForm := TfrmMain.Create(nil);
  try
    Assert.IsTrue(lForm.btnScan.Left < lForm.btnPullVisible.Left);
    Assert.IsTrue(lForm.btnPullVisible.Left < lForm.btnPushVisible.Left);
    Assert.IsTrue(lForm.btnPushVisible.Left < lForm.btnSettings.Left);
  finally
    lForm.Free;
  end;
end;

procedure TUiFormTests.Toolbar_AllActionsHaveDistinctSvgImages;
var
  lForm: TfrmMain;
begin
  lForm := TfrmMain.Create(nil);
  try
    Assert.IsNotNull(lForm.btnScan.Images);
    Assert.AreSame(lForm.btnScan.Images, lForm.btnPullVisible.Images);
    Assert.AreSame(lForm.btnScan.Images, lForm.btnPushVisible.Images);
    Assert.AreSame(lForm.btnScan.Images, lForm.btnSettings.Images);
    Assert.AreNotEqual(lForm.btnScan.ImageIndex, lForm.btnPullVisible.ImageIndex);
    Assert.AreNotEqual(lForm.btnScan.ImageIndex, lForm.btnPushVisible.ImageIndex);
    Assert.AreNotEqual(lForm.btnScan.ImageIndex, lForm.btnSettings.ImageIndex);
    Assert.AreNotEqual(lForm.btnPullVisible.ImageIndex, lForm.btnPushVisible.ImageIndex);
    Assert.AreNotEqual(lForm.btnPullVisible.ImageIndex, lForm.btnSettings.ImageIndex);
    Assert.AreNotEqual(lForm.btnPushVisible.ImageIndex, lForm.btnSettings.ImageIndex);
  finally
    lForm.Free;
  end;
end;

procedure TUiFormTests.ScanActivity_UsesSkillSearchAnimatedControl;
var
  lForm: TfrmMain;
  lAnimation: TComponent;
begin
  lForm := TfrmMain.Create(nil);
  try
    lAnimation := lForm.FindComponent('ScanAnimation');
    Assert.IsNotNull(lAnimation);
    Assert.AreEqual('TSkAnimatedImage', lAnimation.ClassName);
    Assert.IsNotNull(lForm.FindComponent('ActivityPanel'));
  finally
    lForm.Free;
  end;
end;

procedure TUiFormTests.ScanPathsDialog_EscapeCancels;
var
  lForm: TTestScanPathsDialog;
begin
  lForm := TTestScanPathsDialog.Create(nil);
  try
    lForm.ModalResult := mrNone;
    lForm.SendKey(VK_ESCAPE);
    Assert.AreEqual(mrCancel, lForm.ModalResult);
  finally
    lForm.Free;
  end;
end;

procedure TUiFormTests.RepositoryView_UsesVirtualStringTree;
var
  lForm: TfrmMain;
  lTree: TComponent;
begin
  lForm := TfrmMain.Create(nil);
  try
    lTree := lForm.FindComponent('RepoTree');
    Assert.IsNotNull(lTree);
    Assert.AreEqual('TVirtualStringTree', lTree.ClassName);
    Assert.IsNull(lForm.FindComponent('sbRepos'));
    Assert.IsNull(lForm.FindComponent('fpRepos'));
    Assert.AreEqual(72, lForm.RepoTree.DefaultNodeHeight);
    Assert.IsFalse(toAutoChangeScale in lForm.RepoTree.TreeOptions.AutoOptions);
    Assert.AreEqual('Repositories', lForm.RepoTree.AccessibleName);
  finally
    lForm.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TUiFormTests);

end.
